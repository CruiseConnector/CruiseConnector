import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';

/// Herz- und Repost-Knopf fuer einen Beitrag.
///
/// 2026-08-07 (vucko): „schau bitte das man auch likes und reposts auch sieht
/// von seinem posts bei der profilpage."
///
/// Vorher standen diese beiden Knoepfe als private Klassen in
/// community_page.dart. Die Profilseite bekam die Zahlen zwar geladen und
/// sogar als Parameter uebergeben, konnte sie aber nicht anzeigen, weil die
/// Widgets dort nicht erreichbar waren. Sie in der Profilseite ein zweites Mal
/// zu schreiben haette genau denselben Zustand in zwei Fassungen erzeugt und
/// wieder auseinanderlaufen koennen. Deshalb liegen sie jetzt hier, und beide
/// Seiten benutzen dieselben.
///
/// Der Zaehlerstand kommt aus dem CommunityProvider, nicht aus dem
/// uebergebenen Startwert: tippt man in der einen Ansicht auf das Herz,
/// stimmt die Zahl in der anderen sofort mit.
class PostLikeButton extends StatefulWidget {
  const PostLikeButton({
    super.key,
    required this.postId,
    required this.initialCount,
  });

  final String postId;
  final int initialCount;

  @override
  State<PostLikeButton> createState() => _PostLikeButtonState();
}

class _PostLikeButtonState extends State<PostLikeButton> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<CommunityProvider>();
    provider.registerPost({
      'id': widget.postId,
      'likes_count': widget.initialCount,
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) provider.ensureLikedChecked(widget.postId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CommunityProvider>();
    final liked = provider.isLiked(widget.postId);
    final count = provider.likeCount(widget.postId);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.read<CommunityProvider>().toggleLike(widget.postId),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                color: liked ? AppAccentColors.accent : Colors.grey,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  color: liked ? AppAccentColors.accent : Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PostRepostButton extends StatefulWidget {
  const PostRepostButton({
    super.key,
    required this.postId,
    required this.initialCount,
  });

  final String postId;
  final int initialCount;

  @override
  State<PostRepostButton> createState() => _PostRepostButtonState();
}

class _PostRepostButtonState extends State<PostRepostButton> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<CommunityProvider>();
    provider.registerPost({
      'id': widget.postId,
      'reposts_count': widget.initialCount,
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) provider.ensureRepostedChecked(widget.postId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CommunityProvider>();
    final reposted = provider.isReposted(widget.postId);
    final count = provider.repostCount(widget.postId);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          context.read<CommunityProvider>().toggleRepost(widget.postId),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.repeat,
                color: reposted ? const Color(0xFF34C759) : Colors.grey,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  color: reposted ? const Color(0xFF34C759) : Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
