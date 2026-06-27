// 2026-06-27 (vucko) — Onboarding-Wizard. Erscheint NUR bei Account-Erstellung
// (Registrierung + erstes Google/Apple-Login), gegated über
// profiles.onboarding_completed. NICHT beim normalen Login bestehender User.
//
// Clean, mehrseitig (Strava/Komoot/Duolingo-Muster): ein Fokus pro Seite,
// Fortschrittspunkte, klare „Weiter/Überspringen/Fertig". Pflicht: @-Name,
// Anzeigename, Region. Optional/skippbar: Foto, Garage, Freunde.

import 'dart:async';

import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/home_page.dart';
import 'package:cruise_connect/presentation/widgets/photo/ride_photo_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color _bg = Color(0xFF0B0E14);
const Color _card = Color(0xFF161B26);
const Color _accent = Color(0xFFFF6A2C);
const Color _muted = Color(0xFF8A93A6);

enum _UNameState { idle, checking, available, taken, reserved, invalid, error }

class OnboardingWizardPage extends StatefulWidget {
  const OnboardingWizardPage({
    super.key,
    this.initialDisplayName,
    this.initialUsername,
  });

  /// Vorbelegung aus OAuth (Google/Apple liefern oft einen Namen).
  final String? initialDisplayName;
  final String? initialUsername;

  @override
  State<OnboardingWizardPage> createState() => _OnboardingWizardPageState();
}

class _OnboardingWizardPageState extends State<OnboardingWizardPage> {
  final _pageCtrl = PageController();
  int _page = 0;

  // Schritt-Daten
  final _usernameCtrl = TextEditingController();
  final _displayCtrl = TextEditingController();
  final _carBrandCtrl = TextEditingController();
  final _carNameCtrl = TextEditingController();
  String? _country;
  Uint8List? _avatarBytes;
  bool _busy = false;

  // @-Name Live-Check
  Timer? _debounce;
  _UNameState _uState = _UNameState.idle;
  List<String> _suggestions = const [];
  String? _committedUsername;

  static const _totalPages = 7;

  static const _countries = <(String, String)>[
    ('AT', 'Österreich'),
    ('DE', 'Deutschland'),
    ('CH', 'Schweiz'),
    ('IT', 'Italien'),
    ('FR', 'Frankreich'),
    ('LI', 'Liechtenstein'),
    ('Andere', 'Anderes Land'),
  ];

  @override
  void initState() {
    super.initState();
    final dn = widget.initialDisplayName?.trim();
    if (dn != null && dn.isNotEmpty) _displayCtrl.text = dn;
    final un = widget.initialUsername?.trim();
    if (un != null && un.isNotEmpty) {
      _usernameCtrl.text = un;
      _onUsernameChanged(un);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pageCtrl.dispose();
    _usernameCtrl.dispose();
    _displayCtrl.dispose();
    _carBrandCtrl.dispose();
    _carNameCtrl.dispose();
    super.dispose();
  }

  // ── @-Name Verfügbarkeit (debounced, server-seitig) ──────────────────────
  void _onUsernameChanged(String raw) {
    _debounce?.cancel();
    _committedUsername = null;
    final v = raw.trim();
    if (v.isEmpty) {
      setState(() {
        _uState = _UNameState.idle;
        _suggestions = const [];
      });
      return;
    }
    if (!AppInputLimits.isValidUsername(v)) {
      setState(() {
        _uState = _UNameState.invalid;
        _suggestions = const [];
      });
      return;
    }
    setState(() => _uState = _UNameState.checking);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final res = await SocialService.isUsernameAvailable(v);
      if (!mounted || _usernameCtrl.text.trim() != v) return;
      setState(() {
        switch (res.reason) {
          case 'ok':
            _uState = _UNameState.available;
            _suggestions = const [];
          case 'taken':
            _uState = _UNameState.taken;
            _suggestions = _genSuggestions(v);
          case 'reserved':
            _uState = _UNameState.reserved;
            _suggestions = _genSuggestions(v);
          case 'invalid_format':
            _uState = _UNameState.invalid;
            _suggestions = const [];
          default:
            _uState = _UNameState.error;
            _suggestions = const [];
        }
      });
    });
  }

  List<String> _genSuggestions(String base) {
    final b = base.length > 16 ? base.substring(0, 16) : base;
    final out = <String>['${b}1', '${b}_at', 'der_$b', '${b}22'];
    return out
        .where(AppInputLimits.isValidUsername)
        .take(3)
        .toList(growable: false);
  }

  bool get _canLeaveUsernamePage =>
      _uState == _UNameState.available || _committedUsername != null;

  Future<bool> _commitUsername() async {
    final v = _usernameCtrl.text.trim();
    if (_committedUsername == v) return true;
    setState(() => _busy = true);
    try {
      final res = await SocialService.setUsername(v);
      if (res.ok) {
        _committedUsername = v;
        return true;
      }
      _showError(UsernameChangeException(
        res.error ?? 'unknown',
        daysRemaining: res.daysRemaining,
      ).message);
      if (res.error == 'taken' || res.error == 'reserved') {
        setState(() {
          _uState = res.error == 'taken'
              ? _UNameState.taken
              : _UNameState.reserved;
          _suggestions = _genSuggestions(v);
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Navigation ───────────────────────────────────────────────────────────
  Future<void> _next() async {
    // Pflicht-Validierung je Seite + Persistierung
    if (_page == 1) {
      if (!_canLeaveUsernamePage) return;
      if (!await _commitUsername()) return;
    } else if (_page == 2) {
      final name = _displayCtrl.text.trim();
      if (name.isEmpty) {
        _showError('Bitte gib einen Anzeigenamen ein.');
        return;
      }
      setState(() => _busy = true);
      try {
        await SocialService.setDisplayName(name);
      } catch (_) {
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } else if (_page == 3) {
      if (_country == null) {
        _showError('Bitte wähle deine Region.');
        return;
      }
    }
    if (_page >= _totalPages - 1) {
      await _finish();
      return;
    }
    _goTo(_page + 1);
  }

  void _goTo(int p) {
    setState(() => _page = p);
    _pageCtrl.animateToPage(
      p,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _skip() async {
    // Optionale Schritte (Foto/Garage/Freunde) überspringen.
    if (_page >= _totalPages - 1) {
      await _finish();
    } else {
      _goTo(_page + 1);
    }
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    try {
      // Optionale Garage (wenn auf der Garage-Seite was eingegeben wurde)
      final brand = _carBrandCtrl.text.trim();
      final model = _carNameCtrl.text.trim();
      if (brand.isNotEmpty || model.isNotEmpty) {
        try {
          await SocialService.updateCarProfile(
            brand: brand.isEmpty ? null : brand,
            name: model.isEmpty ? null : model,
          );
        } catch (_) {}
      }
      await SocialService.completeOnboarding(
        countryCode: _country == 'Andere' ? null : _country,
        region: _country,
        language: 'de',
      );
    } catch (_) {
      // Onboarding darf nie hängen bleiben — im Zweifel weiter zur App.
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomePage()),
      (r) => false,
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFFB3261E)),
    );
  }

  // ── Foto ─────────────────────────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    final bytes = await pickAndCropRidePhoto(context, lockedAspect: 1);
    if (bytes == null || !mounted) return;
    setState(() {
      _avatarBytes = bytes;
      _busy = true;
    });
    try {
      await SocialService.uploadAvatar(bytes);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isOptional = _page == 4 || _page == 5 || _page == 6;
    final isLast = _page == _totalPages - 1;
    return PopScope(
      canPop: false, // Onboarding nicht per Back verlassen
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              _progress(),
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _welcomeStep(),
                    _usernameStep(),
                    _displayStep(),
                    _regionStep(),
                    _photoStep(),
                    _garageStep(),
                    _friendsStep(),
                  ],
                ),
              ),
              _bottomBar(isOptional: isOptional, isLast: isLast),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progress() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: List.generate(_totalPages, (i) {
          final active = i <= _page;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 4,
              margin: EdgeInsets.only(right: i == _totalPages - 1 ? 0 : 6),
              decoration: BoxDecoration(
                color: active ? _accent : _card,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _bottomBar({required bool isOptional, required bool isLast}) {
    final nextEnabled = !_busy && (_page != 1 || _canLeaveUsernamePage);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Row(
        children: [
          if (_page > 0)
            TextButton(
              onPressed: _busy ? null : () => _goTo(_page - 1),
              child: const Text('Zurück',
                  style: TextStyle(color: _muted, fontSize: 15)),
            ),
          const Spacer(),
          if (isOptional)
            TextButton(
              onPressed: _busy ? null : _skip,
              child: const Text('Überspringen',
                  style: TextStyle(color: _muted, fontSize: 15)),
            ),
          const SizedBox(width: 8),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: nextEnabled ? _next : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                disabledBackgroundColor: _accent.withValues(alpha: 0.35),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _page == 0
                          ? 'Los geht\'s'
                          : isLast
                              ? 'Fertig'
                              : 'Weiter',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepShell({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1.15)),
          const SizedBox(height: 8),
          Text(subtitle,
              style: const TextStyle(color: _muted, fontSize: 15, height: 1.4)),
          const SizedBox(height: 28),
          child,
        ],
      ),
    );
  }

  Widget _welcomeStep() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.directions_car_filled,
                color: _accent, size: 34),
          ),
          const SizedBox(height: 24),
          const Text('Willkommen bei\nCruiseConnect',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.15)),
          const SizedBox(height: 14),
          const Text(
            'Lass uns dein Profil in ein paar Schritten einrichten — '
            'damit andere Cruiser dich finden und du sofort losfahren kannst.',
            style: TextStyle(color: _muted, fontSize: 16, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _usernameStep() {
    return _stepShell(
      title: 'Wähl deinen @-Namen',
      subtitle:
          'Dein eindeutiger Handle — daran finden dich andere. 3–20 Zeichen, '
          'Buchstaben, Zahlen und _.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _usernameCtrl,
            onChanged: _onUsernameChanged,
            autocorrect: false,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
              LengthLimitingTextInputFormatter(AppInputLimits.usernameMaxLength),
            ],
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            decoration: _fieldDeco(
              hint: 'deinname',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 14, right: 2),
                child: Text('@',
                    style: TextStyle(color: _accent, fontSize: 20)),
              ),
              suffix: _uStatusIcon(),
            ),
          ),
          const SizedBox(height: 10),
          _uStatusLine(),
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Vorschläge:',
                style: TextStyle(color: _muted, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _suggestions
                  .map((s) => GestureDetector(
                        onTap: () {
                          _usernameCtrl.text = s;
                          _usernameCtrl.selection = TextSelection.collapsed(
                              offset: s.length);
                          _onUsernameChanged(s);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: _card,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: _accent.withValues(alpha: 0.4)),
                          ),
                          child: Text('@$s',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14)),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget? _uStatusIcon() {
    switch (_uState) {
      case _UNameState.checking:
        return const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _muted)),
        );
      case _UNameState.available:
        return const Icon(Icons.check_circle, color: Color(0xFF2ECC71));
      case _UNameState.taken:
      case _UNameState.reserved:
      case _UNameState.invalid:
        return const Icon(Icons.cancel, color: Color(0xFFE74C3C));
      default:
        return null;
    }
  }

  Widget _uStatusLine() {
    final (String text, Color color) = switch (_uState) {
      _UNameState.available => ('@${_usernameCtrl.text.trim()} ist frei 🎉',
          const Color(0xFF2ECC71)),
      _UNameState.taken => ('Schon vergeben — probier einen Vorschlag.',
          const Color(0xFFE74C3C)),
      _UNameState.reserved => ('Dieser Name ist reserviert.',
          const Color(0xFFE74C3C)),
      _UNameState.invalid => ('3–20 Zeichen: Buchstaben, Zahlen, _ '
          '(kein __, nicht mit _ beginnen/enden).', _muted),
      _UNameState.checking => ('Prüfe Verfügbarkeit…', _muted),
      _UNameState.error => ('Konnte gerade nicht prüfen.', _muted),
      _UNameState.idle => ('', _muted),
    };
    if (text.isEmpty) return const SizedBox(height: 4);
    return Text(text, style: TextStyle(color: color, fontSize: 13.5));
  }

  Widget _displayStep() {
    return _stepShell(
      title: 'Wie sollen dich\nandere sehen?',
      subtitle:
          'Dein Anzeigename (ohne @). Den kannst du jederzeit ändern — der '
          '@-Name bleibt fest.',
      child: TextField(
        controller: _displayCtrl,
        textCapitalization: TextCapitalization.words,
        inputFormatters: [LengthLimitingTextInputFormatter(40)],
        style: const TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        decoration: _fieldDeco(hint: 'Max Mustermann'),
      ),
    );
  }

  Widget _regionStep() {
    return _stepShell(
      title: 'Wo cruisst du?',
      subtitle: 'Hilft uns, dir die besten Routen in deiner Nähe zu zeigen.',
      child: Column(
        children: _countries.map((c) {
          final selected = _country == c.$1;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => setState(() => _country = c.$1),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  color: selected ? _accent.withValues(alpha: 0.14) : _card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? _accent : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Text(c.$2,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (selected)
                      const Icon(Icons.check_circle, color: _accent, size: 22),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _photoStep() {
    return _stepShell(
      title: 'Zeig dich',
      subtitle: 'Ein Profilbild macht dein Profil persönlich. (Optional)',
      child: Center(
        child: GestureDetector(
          onTap: _busy ? null : _pickPhoto,
          child: Column(
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: _card,
                  shape: BoxShape.circle,
                  border: Border.all(color: _accent.withValues(alpha: 0.4)),
                  image: _avatarBytes != null
                      ? DecorationImage(
                          image: MemoryImage(_avatarBytes!), fit: BoxFit.cover)
                      : null,
                ),
                child: _avatarBytes == null
                    ? const Icon(Icons.add_a_photo_outlined,
                        color: _muted, size: 40)
                    : null,
              ),
              const SizedBox(height: 16),
              Text(_avatarBytes == null ? 'Foto auswählen' : 'Foto ändern',
                  style: const TextStyle(color: _accent, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _garageStep() {
    return _stepShell(
      title: 'Was fährst du?',
      subtitle: 'Füg dein erstes Fahrzeug zur Garage hinzu. (Optional)',
      child: Column(
        children: [
          TextField(
            controller: _carBrandCtrl,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [LengthLimitingTextInputFormatter(40)],
            style: const TextStyle(color: Colors.white, fontSize: 17),
            decoration: _fieldDeco(hint: 'Marke (z.B. BMW)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _carNameCtrl,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [LengthLimitingTextInputFormatter(40)],
            style: const TextStyle(color: Colors.white, fontSize: 17),
            decoration: _fieldDeco(hint: 'Modell (z.B. M3)'),
          ),
        ],
      ),
    );
  }

  Widget _friendsStep() {
    return _stepShell(
      title: 'Fast geschafft!',
      subtitle:
          'Freunde findest du jederzeit über Suche & Community. Danach zeigen '
          'wir dir kurz, wie die App funktioniert.',
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            Icon(Icons.group_add_outlined, color: _accent, size: 28),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Du kannst später in der Community Freunden folgen und '
                'gemeinsam cruisen.',
                style:
                    TextStyle(color: Colors.white, fontSize: 14.5, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDeco({
    required String hint,
    Widget? prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF555E70)),
      filled: true,
      fillColor: _card,
      prefixIcon: prefix,
      prefixIconConstraints:
          const BoxConstraints(minWidth: 0, minHeight: 0),
      suffixIcon: suffix,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
    );
  }
}
