import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/providers/app_accent_provider.dart';
import '../../data/services/ride_rating_prompt_service.dart';

/// Das Bewertungs-Popup nach einer abgeschlossenen Fahrt.
///
/// 2026-08-04 (vucko): „Ich möchte, dass sie direkt vier Sterne geben können
/// mit einem Kommentar, ohne dass sie die App verlassen müssen, und dass wir
/// dann im App Store wirklich hochgenommen werden. Auch noch mit dem Text, wie
/// sehr es uns weiterbringen würde."
///
/// WAS TECHNISCH GEHT UND WAS NICHT — damit das später niemand für einen Bug
/// hält: Eine Bewertung landet nur dann im App Store, wenn sie über Apples
/// eigenes Blatt (SKStoreReviewController, hier `InAppReview.requestReview`)
/// abgegeben wird. Dieses Blatt nimmt STERNE entgegen, aber keinen Fließtext.
/// Einen geschriebenen Rezensionstext kann Apple nur auf der Store-Seite
/// annehmen. Deshalb:
///
///   4–5 Sterne → Apples Blatt öffnet sich sofort in der App. Die Sterne
///                zählen für den Store, niemand muss die App verlassen. Wer
///                zusätzlich schreiben will, bekommt einen Link angeboten.
///   1–3 Sterne → KEIN Store. Stattdessen ein Textfeld, das direkt bei uns
///                landet (`app_feedback`). So erfahren wir den Grund, statt
///                ihn öffentlich als Zwei-Sterne-Rezension zu lesen.
///
/// Apple zeigt sein Blatt außerdem nach eigenem Ermessen und höchstens dreimal
/// im Jahr je Nutzer. Passiert nichts sichtbares, ist das kein Fehler unserer
/// App — deshalb behandeln wir den Aufruf als „erledigt", sobald er durch ist.
Future<void> showRideRatingSheet(
  BuildContext context, {
  bool ersteFahrt = true,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: const Color(0xFF11151D),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _RideRatingSheet(ersteFahrt: ersteFahrt),
  );
}

class _RideRatingSheet extends StatefulWidget {
  const _RideRatingSheet({required this.ersteFahrt});

  /// Steuert nur die Ueberschrift. Der Text darunter — kleines Team, keine
  /// Werbebudget, Bewertungen entscheiden — bleibt jedes Mal derselbe.
  final bool ersteFahrt;

  @override
  State<_RideRatingSheet> createState() => _RideRatingSheetState();
}

enum _Schritt { sterne, kommentar, danke }

class _RideRatingSheetState extends State<_RideRatingSheet> {
  _Schritt _schritt = _Schritt.sterne;
  int _sterne = 0;
  bool _sendet = false;
  String _dankeText = '';
  bool _storeLinkAnbieten = false;

  final TextEditingController _kommentar = TextEditingController();

  @override
  void dispose() {
    _kommentar.dispose();
    super.dispose();
  }

  Future<void> _sterneGewaehlt(int sterne) async {
    HapticFeedback.selectionClick();
    setState(() => _sterne = sterne);

    // Kurz stehen lassen, damit man die eigene Auswahl noch sieht.
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;

    if (sterne >= 4) {
      await _apfelBlattOeffnen();
    } else {
      setState(() => _schritt = _Schritt.kommentar);
    }
  }

  Future<void> _apfelBlattOeffnen() async {
    setState(() => _sendet = true);
    try {
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
      }
    } catch (e) {
      debugPrint('[RideRating] Store-Blatt nicht verfuegbar: $e');
    }
    // Egal ob Apple das Blatt tatsächlich gezeigt hat: Wer vier oder fünf
    // Sterne getippt hat, wird nicht noch einmal gefragt.
    await RideRatingPromptService.instance.markSettled();
    if (!mounted) return;
    setState(() {
      _sendet = false;
      _storeLinkAnbieten = true;
      _dankeText =
          'Danke dir. Das hilft uns wirklich weiter — jede Bewertung macht '
          'Cruise Connector für andere Autofahrer sichtbarer.';
      _schritt = _Schritt.danke;
    });
  }

  Future<void> _kommentarSenden() async {
    final text = _kommentar.text.trim();
    // Vor dem ersten await abgreifen — danach ist der Context nicht mehr
    // garantiert gültig.
    final plattform = Theme.of(context).platform.name;
    setState(() => _sendet = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        String? version;
        try {
          final info = await PackageInfo.fromPlatform();
          version = '${info.version}+${info.buildNumber}';
        } catch (_) {
          version = null;
        }
        await Supabase.instance.client.from('app_feedback').insert({
          'user_id': user.id,
          'stars': _sterne,
          'comment': text.isEmpty ? null : text,
          'app_version': version,
          'platform': plattform,
        });
      }
    } catch (e) {
      // Fehlertolerant: Die Rückmeldung geht dann eben verloren. Dem Nutzer
      // hier einen Fehler zu zeigen, bringt ihm nichts — er hat seinen Teil
      // getan.
      debugPrint('[RideRating] Rueckmeldung nicht gespeichert: $e');
    }
    await RideRatingPromptService.instance.markSettled();
    if (!mounted) return;
    setState(() {
      _sendet = false;
      _dankeText =
          'Danke für die ehrliche Rückmeldung. Wir lesen jede einzelne und '
          'arbeiten die Punkte ab.';
      _schritt = _Schritt.danke;
    });
  }

  Future<void> _spaeter() async {
    Navigator.of(context).pop();
  }

  Future<void> _nieWieder() async {
    await RideRatingPromptService.instance.markSettled();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _storeSeiteOeffnen() async {
    try {
      await InAppReview.instance.openStoreListing(appStoreId: _appStoreId);
    } catch (e) {
      debugPrint('[RideRating] Store-Seite nicht geoeffnet: $e');
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// Numerische App-Store-ID. iOS braucht sie für `openStoreListing`; Android
  /// findet den Eintrag über den Paketnamen von allein.
  /// Quelle: https://apps.apple.com/at/app/cruise-connector/id6767208020
  static const String _appStoreId = '6767208020';

  @override
  Widget build(BuildContext context) {
    final unten = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: unten),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              switch (_schritt) {
                _Schritt.sterne => _baueSterneSchritt(),
                _Schritt.kommentar => _baueKommentarSchritt(),
                _Schritt.danke => _baueDankeSchritt(),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _baueSterneSchritt() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppAccentColors.accentSoft,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.emoji_events_rounded,
            color: AppAccentColors.accent,
            size: 30,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          widget.ersteFahrt
              ? 'Erste Fahrt geschafft'
              : 'Wieder eine Runde geschafft',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Cruise Connector wird von einem winzigen Team gebaut, ohne Werbebudget. '
          'Was uns wirklich weiterbringt, sind Bewertungen: Sie entscheiden, ob '
          'andere Autofahrer die App überhaupt zu sehen bekommen. Zwei Sekunden '
          'von dir, und du musst dafür nicht einmal die App verlassen.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 14.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 22),
        if (_sendet)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                _Stern(
                  gefuellt: i <= _sterne,
                  onTap: () => _sterneGewaehlt(i),
                ),
            ],
          ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _sendet ? null : _spaeter,
                child: Text(
                  'Später',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.66),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: _sendet ? null : _nieWieder,
                child: Text(
                  'Nicht mehr fragen',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _baueKommentarSchritt() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Was sollen wir besser machen?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Das geht direkt an uns und nicht in den App Store. Schreib ruhig '
          'ehrlich, was gestört hat — daraus wird die nächste Version gebaut.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _kommentar,
          maxLines: 4,
          maxLength: 1000,
          enabled: !_sendet,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Zum Beispiel: Die Route führte über eine gesperrte Straße.',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
            counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 6),
        ElevatedButton(
          onPressed: _sendet ? null : _kommentarSenden,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppAccentColors.accent,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            elevation: 0,
          ),
          child: _sendet
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Absenden',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _baueDankeSchritt() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.favorite_rounded,
          color: AppAccentColors.accent,
          size: 40,
        ),
        const SizedBox(height: 16),
        Text(
          _dankeText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15.5,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        if (_storeLinkAnbieten) ...[
          TextButton(
            onPressed: _storeSeiteOeffnen,
            child: Text(
              'Noch ein paar Worte schreiben',
              style: TextStyle(
                color: AppAccentColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 2),
        ],
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            elevation: 0,
          ),
          child: const Text(
            'Schließen',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _Stern extends StatelessWidget {
  const _Stern({required this.gefuellt, required this.onTap});

  final bool gefuellt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      iconSize: 40,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      constraints: const BoxConstraints(),
      icon: Icon(
        gefuellt ? Icons.star_rounded : Icons.star_outline_rounded,
        color: gefuellt
            ? const Color(0xFFFFC531)
            : Colors.white.withValues(alpha: 0.34),
      ),
    );
  }
}
