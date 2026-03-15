import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isPrivateAccount = false;
  bool _pushNotifications = true;
  bool _metricUnits = true;

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
        title: const Text("Einstellungen", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader("KONTO & PRIVATSPHÄRE"),
          _buildSectionContainer([
            _buildSwitchTile(
              "Privates Konto",
              _isPrivateAccount,
              (val) => setState(() => _isPrivateAccount = val),
            ),
            const Divider(color: Colors.white10, height: 1),
            _buildNavTile("Passwort ändern", Icons.lock_outline),
          ]),

          const SizedBox(height: 24),

          _buildSectionHeader("APP-EINSTELLUNGEN"),
          _buildSectionContainer([
            _buildSwitchTile(
              "Push-Benachrichtigungen",
              _pushNotifications,
              (val) => setState(() => _pushNotifications = val),
            ),
            const Divider(color: Colors.white10, height: 1),
            _buildSwitchTile(
              "Metrische Einheiten (km)",
              _metricUnits,
              (val) => setState(() => _metricUnits = val),
            ),
          ]),

          const SizedBox(height: 24),

          _buildSectionHeader("GEFAHRENZONE"),
          _buildSectionContainer([
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30)),
              title: const Text(
                "Konto löschen",
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

  Widget _buildSwitchTile(String title, bool value, Function(bool) onChanged) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: const Color(0xFFFF3B30),
        activeTrackColor: const Color(0xFFFF3B30).withOpacity(0.3),
        inactiveThumbColor: Colors.grey,
        inactiveTrackColor: Colors.grey.withOpacity(0.3),
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