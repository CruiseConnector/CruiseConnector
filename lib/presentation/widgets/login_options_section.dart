import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/auth_service.dart';

/// 2026-06-16 (vucko): Einstellungen-Sektion „Anmeldeoptionen".
/// Ein Account, mehrere Login-Wege: zeigt die verknüpften Identitäten
/// (E-Mail / Apple / Google) und erlaubt Verbinden bzw. Trennen. So kommt
/// man — egal mit welcher Methode — immer in denselben Account.
class LoginOptionsSection extends StatefulWidget {
  const LoginOptionsSection({super.key});

  @override
  State<LoginOptionsSection> createState() => _LoginOptionsSectionState();
}

class _LoginOptionsSectionState extends State<LoginOptionsSection> {
  List<UserIdentity> _identities = const [];
  bool _loading = true;
  String? _busyProvider;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = await AuthService.linkedIdentities();
    if (!mounted) return;
    setState(() {
      _identities = ids;
      _loading = false;
    });
  }

  UserIdentity? _identityFor(String provider) {
    for (final i in _identities) {
      if (i.provider == provider) return i;
    }
    return null;
  }

  String _label(String provider) {
    switch (provider) {
      case 'email':
        return 'E-Mail';
      case 'apple':
        return 'Apple';
      case 'google':
        return 'Google';
      default:
        return provider;
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            error ? const Color(0xFFB3261E) : const Color(0xFF2D3748),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _connect(String provider) async {
    setState(() => _busyProvider = provider);
    try {
      if (provider == 'apple') {
        await AuthService.linkApple();
      } else if (provider == 'google') {
        await AuthService.linkGoogle();
      }
      await _load();
      _toast('${_label(provider)} verbunden.');
    } on AuthException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast('${_label(provider)} verbinden fehlgeschlagen.', error: true);
    } finally {
      if (mounted) setState(() => _busyProvider = null);
    }
  }

  Future<void> _disconnect(UserIdentity identity) async {
    if (_identities.length <= 1) {
      _toast('Mindestens eine Anmeldeoption muss bleiben.', error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1E28),
        title: Text(
          '${_label(identity.provider)} trennen?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          'Du kannst dich danach nicht mehr über ${_label(identity.provider)} '
          'in diesen Account einloggen.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Trennen',
              style: TextStyle(color: Color(0xFFE24B4A)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busyProvider = identity.provider);
    try {
      await AuthService.unlinkProvider(identity);
      await _load();
      _toast('${_label(identity.provider)} getrennt.');
    } on AuthException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast('Trennen fehlgeschlagen.', error: true);
    } finally {
      if (mounted) setState(() => _busyProvider = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final emailIdentity = _identityFor('email');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            'ANMELDEOPTIONEN',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(16),
          ),
          child: _loading
              ? Padding(
                  padding: const EdgeInsets.all(22),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (emailIdentity != null) ...[
                      _buildRow(
                        icon: Icons.mail_outline,
                        label: 'E-Mail',
                        identity: emailIdentity,
                      ),
                      const Divider(color: Colors.white10, height: 1),
                    ],
                    // 2026-06-25 (vucko): Apple-Verbinden NUR auf iOS (nativ).
                    // Auf Android fehlt der Supabase-Apple-Browser-OAuth-Secret
                    // → „Verbinden" würde scheitern. Wer Apple aber schon (auf
                    // iOS) verknüpft hat, sieht/trennt es auch auf Android.
                    if ((!kIsWeb && Platform.isIOS) ||
                        _identityFor('apple') != null) ...[
                      _buildRow(
                        icon: Icons.apple,
                        label: 'Apple',
                        identity: _identityFor('apple'),
                        provider: 'apple',
                      ),
                      const Divider(color: Colors.white10, height: 1),
                    ],
                    _buildRow(
                      icon: Icons.g_mobiledata,
                      label: 'Google',
                      identity: _identityFor('google'),
                      provider: 'google',
                    ),
                  ],
                ),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 12, top: 6),
          child: Text(
            'Verbinde weitere Wege, um dich künftig auch darüber in denselben '
            'Account einzuloggen.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildRow({
    required IconData icon,
    required String label,
    UserIdentity? identity,
    String? provider,
  }) {
    final accent = AppAccentColors.accent;
    final connected = identity != null;
    final busy = provider != null && _busyProvider == provider;
    final email = identity?.identityData?['email'] as String?;

    Widget trailing;
    if (busy) {
      trailing = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: accent),
      );
    } else if (connected) {
      trailing = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: Color(0xFF34D399), size: 18),
          SizedBox(width: 6),
          Text(
            'Verbunden',
            style: TextStyle(color: Color(0xFF34D399), fontSize: 13),
          ),
        ],
      );
    } else {
      trailing = Text(
        'Verbinden',
        style: TextStyle(
          color: accent,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    String? subtitle;
    if (connected && email != null && email.isNotEmpty) {
      subtitle = email;
    } else if (!connected && provider != null) {
      subtitle = 'Tippen zum Verbinden';
    }

    final tappable = provider != null && !busy;
    return ListTile(
      leading: Icon(icon, color: Colors.grey),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            )
          : null,
      trailing: trailing,
      onTap: !tappable
          ? null
          : connected
          ? () => _disconnect(identity)
          : () => _connect(provider),
    );
  }
}
