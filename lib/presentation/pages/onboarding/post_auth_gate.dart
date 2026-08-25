// 2026-06-27 (vucko) — Entscheidet nach erfolgreicher Anmeldung, ob der
// Onboarding-Wizard kommt (neuer Account: profiles.onboarding_completed=false)
// oder direkt die App (HomePage). Bestehende User (Login) sind als onboarded
// markiert => sofort HomePage. EIN zentraler Entscheidungspunkt für alle
// Auth-Einstiege (Registrierung, Login, Google/Apple, Session-Restore).
//
// 2026-08-24 (vucko, nach dem Vorfall „Nutzer sitzt fest"): Dieses Tor ist die
// Stelle, die JEDER Nutzer nach JEDER Anmeldung durchläuft — und es hatte
// genau einen Ausgang: die Antwort des Servers. Fehler waren abgefangen (sie
// fallen defensiv auf die Startseite), ein Hänger nicht: `needsOnboarding()`
// hatte keine Zeitgrenze, also drehte sich der Ladekreis bei schlechtem Netz
// endlos. Kein Abbrechen, kein Zurück, kein Neustart-Ausweg — die Prüfung lief
// nach dem Neustart ja wieder ins selbe Loch.
//
// Die Regel ab heute: Es muss immer mindestens einen Weg nach draußen geben,
// der ohne Netz und ohne Antwort des Servers funktioniert. Hier sind es drei:
//
//  1. `SocialService.needsOnboarding()` hat jetzt selbst eine Zeitgrenze und
//     wirft danach — der Hänger wird also zu einem sichtbaren Zustand.
//  2. Schon VOR dieser Grenze (nach `wartezeitBisAusweg`) erscheinen unter dem
//     Ladekreis Knöpfe. Das Tor darf warten, aber der Nutzer muss dort etwas
//     tun können.
//  3. Die Knöpfe brauchen kein Netz: „Erneut versuchen" startet die Prüfung
//     neu, „Trotzdem zur App" geht ohne Prüfung weiter, „Abmelden" führt zur
//     Startseite zurück (auch wenn das Abmelden selbst hängt).
//
// Warum „Trotzdem zur App" vertretbar ist, obwohl ein neuer Account dann ohne
// @-Namen in der App landen könnte: `onboarding_completed` bleibt in der
// Datenbank auf false. Beim nächsten Start läuft dieses Tor erneut und holt
// den Wizard nach, sobald das Netz wieder da ist. Das übersprungene Onboarding
// ist also ein Aufschub, keine Sackgasse — Festsitzen dagegen wäre eine.
// Deshalb entscheidet das Tor auch NICHT still von selbst: Wer gerade ein Konto
// erstellt hat, soll den Wizard bekommen und nicht wortlos daran vorbeirutschen.

import 'dart:async';

import 'package:cruise_connect/data/services/auth_service.dart';
import 'package:cruise_connect/data/services/map_style_service.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/home_page.dart';
import 'package:cruise_connect/presentation/pages/onboarding/onboarding_wizard_page.dart';
import 'package:cruise_connect/presentation/pages/welcome_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

const Color _bg = Color(0xFF0B0E14);
const Color _accent = Color(0xFFFF6A2C);
const Color _muted = Color(0xFF8A93A6);

class PostAuthGate extends StatefulWidget {
  const PostAuthGate({
    super.key,
    this.onboardingPruefung,
    this.wartezeitBisAusweg = const Duration(seconds: 8),
  });

  /// Nur für Tests: ersetzt die Server-Prüfung. Produktiv immer
  /// `SocialService.needsOnboarding`.
  final Future<bool> Function()? onboardingPruefung;

  /// Solange dreht sich nur der Ladekreis. Danach bekommt der Nutzer sichtbare
  /// Auswege — auch dann, wenn die Prüfung noch läuft.
  final Duration wartezeitBisAusweg;

  @override
  State<PostAuthGate> createState() => _PostAuthGateState();
}

class _PostAuthGateState extends State<PostAuthGate> {
  late Future<bool> _needs;
  Timer? _auswegTimer;
  bool _zeigeAusweg = false;
  bool _ohnePruefungWeiter = false;
  bool _meldetAb = false;

  @override
  void initState() {
    super.initState();
    // Offline-Karte nach Login/Registrierung/Session-Restore automatisch laden,
    // falls noch nicht vorhanden (nur WLAN, idempotent, im Hintergrund). Startet
    // früher als der Home-Prewarm, damit die Karte direkt nach dem Anmelden lädt.
    if (!kIsWeb) {
      MapStyleService.instance.ensureAutoDownloadScheduled(reason: 'post_auth');
    }
    _startePruefung();
  }

  @override
  void dispose() {
    _auswegTimer?.cancel();
    super.dispose();
  }

  void _startePruefung() {
    _auswegTimer?.cancel();
    _zeigeAusweg = false;
    _needs = (widget.onboardingPruefung ?? SocialService.needsOnboarding)();
    // Der Ausweg hängt an einem eigenen Timer, NICHT an der Antwort des
    // Servers. Genau deshalb erscheint er auch dann, wenn nie eine Antwort
    // kommt — der Fall aus dem Vorfall.
    _auswegTimer = Timer(widget.wartezeitBisAusweg, () {
      if (mounted) setState(() => _zeigeAusweg = true);
    });
  }

  void _erneutVersuchen() {
    setState(_startePruefung);
  }

  void _trotzdemZurApp() {
    _auswegTimer?.cancel();
    setState(() => _ohnePruefungWeiter = true);
  }

  Future<void> _abmelden() async {
    if (_meldetAb) return;
    setState(() => _meldetAb = true);
    try {
      // Auch das Abmelden darf den Nutzer nicht festhalten: nach der Zeitgrenze
      // geht es so oder so zur Startseite. Die lokale Session wird beim
      // nächsten Start ohnehin neu geprüft.
      await AuthService.signOut().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[PostAuthGate] Abmelden fehlgeschlagen/hängt: $e');
    }
    if (!mounted) return;
    _auswegTimer?.cancel();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomePage()),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_ohnePruefungWeiter) return const HomePage();
    return FutureBuilder<bool>(
      future: _needs,
      builder: (context, snap) {
        final laeuftNoch = snap.connectionState != ConnectionState.done;
        // Antwort da → der Ausweg-Timer wird nicht mehr gebraucht.
        if (!laeuftNoch) _auswegTimer?.cancel();
        if (laeuftNoch) {
          return _Wartebildschirm(
            zeigeAusweg: _zeigeAusweg,
            meldetAb: _meldetAb,
            hinweis:
                'Das dauert länger als sonst. Prüfe deine Verbindung, oder '
                'geh einfach weiter, wir holen das später nach.',
            erneutVersuchen: _erneutVersuchen,
            trotzdemZurApp: _trotzdemZurApp,
            abmelden: _abmelden,
          );
        }
        if (snap.hasError) {
          // Hierher kommt nur, was `needsOnboarding` NICHT still schluckt:
          // die abgelaufene Zeitgrenze. Fachliche Fehler fallen dort weiterhin
          // defensiv auf false (= App), damit bestehende Nutzer nicht grundlos
          // ins Onboarding geschickt werden.
          return _Wartebildschirm(
            zeigeAusweg: true,
            meldetAb: _meldetAb,
            laedt: false,
            hinweis:
                'Wir konnten dein Profil gerade nicht laden. Der Server '
                'antwortet nicht.',
            erneutVersuchen: _erneutVersuchen,
            trotzdemZurApp: _trotzdemZurApp,
            abmelden: _abmelden,
          );
        }
        // Bei false => App (defensiv: Onboarding nie erzwingen, wenn unklar;
        // der Wizard ist nur für eindeutig neue Accounts).
        return snap.data == true
            ? const OnboardingWizardPage()
            : const HomePage();
      },
    );
  }
}

/// Ladekreis mit Auswegen. Ohne `zeigeAusweg` sieht er aus wie vorher — die
/// 99 %, bei denen die Prüfung in Millisekunden zurückkommt, merken nichts.
class _Wartebildschirm extends StatelessWidget {
  const _Wartebildschirm({
    required this.zeigeAusweg,
    required this.hinweis,
    required this.erneutVersuchen,
    required this.trotzdemZurApp,
    required this.abmelden,
    required this.meldetAb,
    this.laedt = true,
  });

  final bool zeigeAusweg;
  final bool laedt;
  final bool meldetAb;
  final String hinweis;
  final VoidCallback erneutVersuchen;
  final VoidCallback trotzdemZurApp;
  final Future<void> Function() abmelden;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (laedt)
                  const CircularProgressIndicator(color: _accent)
                else
                  const Icon(Icons.cloud_off_rounded, color: _muted, size: 44),
                if (zeigeAusweg) ...[
                  const SizedBox(height: 22),
                  Text(
                    hinweis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _muted, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: meldetAb ? null : erneutVersuchen,
                      child: const Text('Erneut versuchen'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF2A3040)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: meldetAb ? null : trotzdemZurApp,
                      child: const Text('Trotzdem zur App'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: meldetAb ? null : () => abmelden(),
                    child: const Text(
                      'Abmelden',
                      style: TextStyle(color: _muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
