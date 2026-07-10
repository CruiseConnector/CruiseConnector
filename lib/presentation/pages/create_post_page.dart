import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/widgets/badge_unlock_popup.dart';
import 'package:cruise_connect/presentation/widgets/social/group_attachment_card.dart';
import 'package:cruise_connect/presentation/widgets/social/route_attachment_card.dart';

class CreatePostPage extends StatefulWidget {
  final String? initialText;
  final String? sharedRouteId;
  final String? sharedGroupId;
  const CreatePostPage({
    super.key,
    this.initialText,
    this.sharedRouteId,
    this.sharedGroupId,
  });

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final _controller = TextEditingController();
  bool _posting = false;
  bool _checkingRoutePost = false;
  bool _routeAlreadyPosted = false;
  // 2026-07-03 (vucko Gruppen-Share): Dubletten-Flags gespiegelt vom Routen-Share.
  bool _checkingGroupPost = false;
  bool _groupAlreadyPosted = false;
  String _visibility = 'public'; // 'public' oder 'followers'

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null) {
      final initialText = widget.initialText!;
      _controller.text =
          initialText.length <= AppInputLimits.postContentMaxLength
          ? initialText
          : initialText.substring(0, AppInputLimits.postContentMaxLength);
    }
    _checkRoutePostAvailability();
    _checkGroupPostAvailability();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitPost() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _routeAlreadyPosted || _groupAlreadyPosted) return;

    setState(() => _posting = true);
    try {
      await SocialService.createPost(
        content,
        visibility: _visibility,
        sharedRouteId: widget.sharedRouteId,
        sharedGroupId: widget.sharedGroupId,
      );
      if (!mounted) return;
      final gamResult = await GamificationService.calculateAndSync();
      if (!mounted) return;
      if (gamResult.newBadges.isNotEmpty) {
        await showBadgeUnlockPopup(
          context: context,
          badges: gamResult.newBadges,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on DuplicateSharedRoutePostException catch (e) {
      if (mounted) {
        setState(() {
          _posting = false;
          _routeAlreadyPosted = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: const Color(0xFF1C1F26),
          ),
        );
      }
    } on DuplicateSharedGroupPostException catch (e) {
      if (mounted) {
        setState(() {
          _posting = false;
          _groupAlreadyPosted = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: const Color(0xFF1C1F26),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _posting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Erstellen des Posts'),
            backgroundColor: Color(0xFF1C1F26),
          ),
        );
      }
    }
  }

  Future<void> _checkRoutePostAvailability() async {
    final routeId = widget.sharedRouteId;
    if (routeId == null || routeId.trim().isEmpty) return;

    setState(() => _checkingRoutePost = true);
    try {
      final alreadyPosted = await SocialService.hasOwnPostForSharedRoute(
        routeId,
      );
      if (!mounted) return;
      setState(() {
        _routeAlreadyPosted = alreadyPosted;
        _checkingRoutePost = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingRoutePost = false);
    }
  }

  // 2026-07-03 (vucko Gruppen-Share): Dubletten-Check gespiegelt vom Routen-Share.
  Future<void> _checkGroupPostAvailability() async {
    final groupId = widget.sharedGroupId;
    if (groupId == null || groupId.trim().isEmpty) return;

    setState(() => _checkingGroupPost = true);
    try {
      final alreadyPosted = await SocialService.hasOwnPostForSharedGroup(
        groupId,
      );
      if (!mounted) return;
      setState(() {
        _groupAlreadyPosted = alreadyPosted;
        _checkingGroupPost = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingGroupPost = false);
    }
  }

  Widget _buildVisibilityChip(String value, IconData icon, String label) {
    final selected = _visibility == value;
    return GestureDetector(
      onTap: () => setState(() => _visibility = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppAccentColors.accent : const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppAccentColors.accent : Colors.grey[700]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : Colors.grey),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.grey,
                fontSize: 14,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasContent = _controller.text.trim().isNotEmpty;
    final canPost =
        hasContent &&
        !_posting &&
        !_checkingRoutePost &&
        !_routeAlreadyPosted &&
        !_checkingGroupPost &&
        !_groupAlreadyPosted;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        elevation: 0,
        leadingWidth: 132,
        leading: Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              minimumSize: const Size(112, 48),
              padding: const EdgeInsets.only(left: 6, right: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Abbrechen',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 10, bottom: 10),
            child: ElevatedButton(
              onPressed: canPost ? _submitPost : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppAccentColors.accent,
                disabledBackgroundColor: AppAccentColors.accent.withValues(
                  alpha: 0.3,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: _posting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Posten',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Sichtbarkeits-Toggle
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                _buildVisibilityChip('public', Icons.public, 'Alle'),
                const SizedBox(width: 8),
                _buildVisibilityChip('followers', Icons.group, 'Follower'),
              ],
            ),
          ),
          if (widget.sharedRouteId != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: RouteAttachmentCard(
                routeId: widget.sharedRouteId!,
                compact: true,
                showRideButton: false,
              ),
            ),
            if (_routeAlreadyPosted)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Color(0xFFFFD166),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        SocialService.duplicateSharedRoutePostMessage,
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          // 2026-07-03 (vucko Gruppen-Share): Gruppen-Vorschau analog zur Route,
          // ohne Beitreten-Button (nur Vorschau im Composer).
          if (widget.sharedGroupId != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: GroupAttachmentCard(
                groupId: widget.sharedGroupId!,
                compact: true,
                showJoinButton: false,
              ),
            ),
            if (_groupAlreadyPosted)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Color(0xFFFFD166),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        SocialService.duplicateSharedGroupPostMessage,
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const Divider(color: Color(0xFF1C1F26), height: 1),
          // Post-Eingabe
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey[800],
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      maxLines: null,
                      maxLength: AppInputLimits.postContentMaxLength,
                      onChanged: (_) => setState(() {}),
                      buildCounter:
                          (
                            context, {
                            required currentLength,
                            required isFocused,
                            required maxLength,
                          }) => Text(
                            '$currentLength/$maxLength',
                            style: TextStyle(
                              color:
                                  currentLength >=
                                      AppInputLimits.postContentMaxLength
                                  ? AppAccentColors.accent
                                  : Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                      decoration: const InputDecoration(
                        hintText: "Was gibt's Neues?",
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 18),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
