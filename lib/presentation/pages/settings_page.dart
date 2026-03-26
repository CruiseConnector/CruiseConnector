import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isPrivateAccount = false;
  bool _pushNotifications = true;
  bool _metricUnits = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('is_private')
          .eq('id', uid)
          .single();
      if (mounted) {
        setState(() {
          _isPrivateAccount = data['is_private'] ?? false;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Settings] Privacy laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePrivacy(bool newValue) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: Text(
          newValue ? 'Konto privat machen?' : 'Konto öffentlich machen?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          newValue
              ? 'Wenn dein Konto privat ist, können nur deine Follower deine Posts sehen. '
                'Deine Posts erscheinen nicht mehr im Entdecken-Bereich für andere User.'
              : 'Wenn dein Konto öffentlich ist, kann jeder deine Posts im Entdecken-Bereich sehen.',
          style: const TextStyle(color: Colors.grey, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              newValue ? 'Privat machen' : 'Öffentlich machen',
              style: const TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    setState(() => _isPrivateAccount = newValue);
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'is_private': newValue})
          .eq('id', uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newValue ? 'Dein Konto ist jetzt privat' : 'Dein Konto ist jetzt öffentlich'),
            backgroundColor: const Color(0xFF1C1F26),
          ),
        );
      }
    } catch (e) {
      debugPrint('[Settings] Privacy-Toggle fehlgeschlagen: $e');
      // Rollback
      if (mounted) {
        setState(() => _isPrivateAccount = !newValue);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Speichern'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Einstellungen', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF3B30)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionHeader('KONTO & PRIVATSPHÄRE'),
                _buildSectionContainer([
                  _buildSwitchTile(
                    'Privates Konto',
                    _isPrivateAccount,
                    _togglePrivacy,
                    subtitle: _isPrivateAccount
                        ? 'Nur Follower sehen deine Posts'
                        : 'Jeder kann deine Posts sehen',
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  _buildNavTile('Passwort ändern', Icons.lock_outline),
                ]),

                const SizedBox(height: 24),

                _buildSectionHeader('APP-EINSTELLUNGEN'),
                _buildSectionContainer([
                  _buildSwitchTile(
                    'Push-Benachrichtigungen',
                    _pushNotifications,
                    (val) => setState(() => _pushNotifications = val),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  _buildSwitchTile(
                    'Metrische Einheiten (km)',
                    _metricUnits,
                    (val) => setState(() => _metricUnits = val),
                  ),
                ]),

                const SizedBox(height: 24),

                _buildSectionHeader('GEFAHRENZONE'),
                _buildSectionContainer([
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30)),
                    title: const Text(
                      'Konto löschen',
                      style: TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.bold),
                    ),
                    onTap: () {
                      // Delete logic
                    },
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0),
      ),
    );
  }

  Widget _buildSectionContainer(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSwitchTile(String title, bool value, Function(bool) onChanged, {String? subtitle}) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12))
          : null,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: const Color(0xFFFF3B30),
        activeTrackColor: const Color(0xFFFF3B30).withValues(alpha: 0.3),
        inactiveThumbColor: Colors.grey,
        inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildNavTile(String title, IconData icon) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () {
        // Navigation logic
      },
    );
  }
}
