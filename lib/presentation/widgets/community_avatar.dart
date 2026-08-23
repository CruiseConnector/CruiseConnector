import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

/// 2026-08-23 (Auftrag Vucko, Sprachnachricht): „...dass man für Communities
/// wirklich auch Profilbilder reintun kann..."
///
/// Gemessen am 23.08.2026: `public.communities` hatte genau 9 Spalten und kein
/// Bildfeld, es gab keinen Bucket dafür, und an allen drei Anzeigestellen
/// (Karte in der Übersicht, AppBar und Kopfzeile im Chat) stand fest
/// verdrahtet ein Icon-Platzhalter. Dieses Widget ist das Gegenstück zu
/// [UserAvatar] für Communities: ein Ort für Bild, Platzhalter und Ecken,
/// damit die drei Stellen nicht wieder auseinanderlaufen.
///
/// Anders als [UserAvatar] ist die Form ein abgerundetes Quadrat, weil die
/// Community-Kachel schon immer `borderRadius: 12` auf einem 42x42-Feld hatte
/// und ein plötzlicher Kreis die Übersicht umbauen würde.
class CommunityAvatar extends StatelessWidget {
  const CommunityAvatar({
    super.key,
    this.avatarUrl,
    required this.isPublic,
    this.size = 42,
    this.borderRadius = 12,
    this.onTap,
  });

  /// Bequemer Weg direkt aus einer Community-Zeile (aus `_communitySelect`
  /// oder aus der RPC `find_community_by_code`). Beide liefern `avatar_url`
  /// und `is_public`; fehlt die Zeile, bleibt der Platzhalter.
  factory CommunityAvatar.fromCommunity(
    Map<String, dynamic>? community, {
    Key? key,
    double size = 42,
    double borderRadius = 12,
    VoidCallback? onTap,
  }) {
    return CommunityAvatar(
      key: key,
      avatarUrl: community?['avatar_url']?.toString(),
      isPublic: community?['is_public'] == true,
      size: size,
      borderRadius: borderRadius,
      onTap: onTap,
    );
  }

  /// Öffentliche URL aus dem Bucket `community_images`, mit Cache-Buster.
  final String? avatarUrl;

  /// Bestimmt nur den Platzhalter: öffentlich zeigt ein Forum-Symbol,
  /// privat ein Schloss. Genau wie vor dieser Änderung.
  final bool isPublic;

  final double size;
  final double borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();
    final hasImage = url != null && url.isNotEmpty;

    Widget content = _buildPlaceholder();
    if (hasImage) {
      final provider = UserAvatar.resizedNetworkImageProvider(
        context,
        url,
        width: size,
        height: size,
      );
      if (provider != null) {
        content = Image(
          image: provider,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // Eine tote URL (Bild im Bucket gelöscht, Netz weg) darf kein
          // graues Loch hinterlassen — dann gilt wieder der Platzhalter.
          errorBuilder: (_, _, _) => _buildPlaceholder(),
          frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return _buildPlaceholder();
          },
        );
      }
    }

    final avatar = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(width: size, height: size, child: content),
    );

    if (onTap == null) return avatar;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(borderRadius),
      child: avatar,
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: size,
      height: size,
      color: AppAccentColors.accent.withValues(alpha: 0.18),
      alignment: Alignment.center,
      child: Icon(
        isPublic ? Icons.forum_outlined : Icons.lock_outline,
        color: AppAccentColors.accent,
        size: size * 0.52,
      ),
    );
  }
}
