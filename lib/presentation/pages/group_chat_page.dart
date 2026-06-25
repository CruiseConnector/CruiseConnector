import 'package:flutter/material.dart';

import 'package:cruise_connect/presentation/widgets/group_chat_panel.dart';

/// 2026-06-25 (vucko): Vollbild-Gruppenchat, erreichbar aus der Lobby. Dünner
/// Wrapper um [GroupChatPanel] — die ganze Logik (Realtime, Senden, Löschen)
/// liegt im Panel, damit es bei Bedarf auch als Tab eingebettet werden kann.
class GroupChatPage extends StatelessWidget {
  const GroupChatPage({super.key, required this.groupId, this.groupName});

  final String groupId;
  final String? groupName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              groupName?.trim().isNotEmpty == true ? groupName! : 'Gruppen-Chat',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const Text(
              'Gruppen-Chat',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
      body: GroupChatPanel(groupId: groupId),
    );
  }
}
