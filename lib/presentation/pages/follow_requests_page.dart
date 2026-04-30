import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/user_profile_page.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

/// Übersicht aller offenen Follow-Anfragen — erreichbar über das
/// Burger-Menü auf der Profil-Seite.
class FollowRequestsPage extends StatefulWidget {
  const FollowRequestsPage({super.key});

  @override
  State<FollowRequestsPage> createState() => _FollowRequestsPageState();
}

class _FollowRequestsPageState extends State<FollowRequestsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _requests = [];
  // IDs, die gerade akzeptiert/abgelehnt werden — disable Buttons.
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await SocialService.getPendingFollowRequests();
      if (mounted) {
        setState(() {
          _requests = list;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[FollowRequests] Laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handle(Map<String, dynamic> request, bool accept) async {
    final fromId = request['follower_id'] as String?;
    if (fromId == null || _busy.contains(fromId)) return;
    setState(() => _busy.add(fromId));
    try {
      final provider = context.read<CommunityProvider>();
      if (accept) {
        await provider.acceptFollowRequest(fromId);
      } else {
        await provider.rejectFollowRequest(fromId);
      }
      if (mounted) {
        setState(() {
          _requests.removeWhere((r) => r['follower_id'] == fromId);
        });
      }
    } catch (e) {
      debugPrint('[FollowRequests] Aktion fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(fromId));
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
        title: const Text(
          'Freundschaftsanfragen',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF3B30)))
          : _requests.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined,
                            color: Colors.grey, size: 48),
                        SizedBox(height: 12),
                        Text(
                          'Keine offenen Anfragen',
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
                    itemCount: _requests.length,
                    separatorBuilder: (_, _) =>
                        const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, i) =>
                        _buildRequestTile(_requests[i]),
                  ),
                ),
    );
  }

  Widget _buildRequestTile(Map<String, dynamic> request) {
    final profile = request['profiles'] as Map<String, dynamic>?;
    final fromId = request['follower_id'] as String?;
    final username =
        (profile?['username'] ?? profile?['email']?.split('@')[0] ?? 'User')
            .toString();
    final isBusy = fromId != null && _busy.contains(fromId);

    return ListTile(
      onTap: fromId == null
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserProfilePage(
                    userId: fromId,
                    initialUsername: username,
                  ),
                ),
              ),
      leading: UserAvatar.fromProfile(
        profile,
        fallbackName: username,
        radius: 22,
      ),
      title: Text(username,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: const Text('möchte dir folgen',
          style: TextStyle(color: Colors.grey, fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: isBusy ? null : () => _handle(request, true),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isBusy
                    ? const Color(0xFFFF3B30).withValues(alpha: 0.4)
                    : const Color(0xFFFF3B30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Annehmen',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: isBusy ? null : () => _handle(request, false),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Ablehnen',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
