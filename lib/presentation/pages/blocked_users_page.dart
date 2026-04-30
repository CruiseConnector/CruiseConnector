import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

/// Übersicht der von mir blockierten Nutzer mit „Entblocken"-Button.
/// Erreichbar über das Burger-Menü auf der Profil-Seite.
class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _blocked = [];
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await SocialService.getBlockedUsers();
      if (mounted) {
        setState(() {
          _blocked = list;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[BlockedUsers] Laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(Map<String, dynamic> entry) async {
    final blockedId = entry['blocked_id'] as String?;
    if (blockedId == null || _busy.contains(blockedId)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text('Entblocken?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Der Nutzer kann dann wieder deine Inhalte sehen und du seine.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Abbrechen', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Entblocken',
                style: TextStyle(
                    color: Color(0xFFFF3B30), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy.add(blockedId));
    try {
      if (!mounted) return;
      await context.read<CommunityProvider>().unblockUser(blockedId);
      if (mounted) {
        setState(() {
          _blocked.removeWhere((e) => e['blocked_id'] == blockedId);
        });
      }
    } catch (e) {
      debugPrint('[BlockedUsers] Entblocken fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Entblocken fehlgeschlagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(blockedId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Blockierte Nutzer',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF3B30)))
          : _blocked.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.block, color: Colors.grey, size: 48),
                        SizedBox(height: 12),
                        Text(
                          'Du hast niemanden blockiert.',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: const Color(0xFFFF3B30),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _blocked.length,
                    separatorBuilder: (_, _) =>
                        const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, i) => _buildTile(_blocked[i]),
                  ),
                ),
    );
  }

  Widget _buildTile(Map<String, dynamic> entry) {
    final profile = entry['profiles'] as Map<String, dynamic>?;
    final blockedId = entry['blocked_id'] as String?;
    final username =
        (profile?['username'] ?? profile?['email']?.split('@')[0] ?? 'User')
            .toString();
    final isBusy = blockedId != null && _busy.contains(blockedId);

    return ListTile(
      leading: UserAvatar.fromProfile(
        profile,
        fallbackName: username,
        radius: 22,
      ),
      title: Text(
        '@$username',
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600),
      ),
      subtitle: const Text('blockiert',
          style: TextStyle(color: Colors.grey, fontSize: 12)),
      trailing: GestureDetector(
        onTap: isBusy ? null : () => _unblock(entry),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFFF3B30)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: isBusy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFFFF3B30)))
              : const Text(
                  'Entblocken',
                  style: TextStyle(
                    color: Color(0xFFFF3B30),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}
