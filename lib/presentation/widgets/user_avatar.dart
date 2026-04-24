import 'package:flutter/material.dart';

/// Wiederverwendbarer Avatar mit Bild-Fallback auf Initiale.
/// Nimmt entweder eine [avatarUrl] oder direkt ein [profile]-Map (z.B. aus
/// `posts.profiles`-Joins).
class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final double radius;
  final Color backgroundColor;
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.radius = 20,
    this.backgroundColor = const Color(0xFFFF3B30),
    this.onTap,
  });

  /// Convenience-Konstruktor: liest `avatar_url` und `username`/`email` aus
  /// einem Profile-Map (typischerweise aus `posts.profiles`-Joins). Liefert
  /// einen sauberen Avatar, auch wenn das Profile null ist.
  factory UserAvatar.fromProfile(
    Map<String, dynamic>? profile, {
    Key? key,
    String? fallbackName,
    double radius = 20,
    Color backgroundColor = const Color(0xFFFF3B30),
    VoidCallback? onTap,
  }) {
    final username = profile?['username'] as String?;
    final email = profile?['email'] as String?;
    final url = profile?['avatar_url'] as String?;
    final resolvedName =
        username ?? email?.split('@').first ?? fallbackName ?? 'User';
    return UserAvatar(
      key: key,
      name: resolvedName,
      avatarUrl: url,
      radius: radius,
      backgroundColor: backgroundColor,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'U';
    final hasUrl = avatarUrl != null && avatarUrl!.trim().isNotEmpty;

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      backgroundImage: hasUrl ? NetworkImage(avatarUrl!) : null,
      child: hasUrl
          ? null
          : Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.9,
              ),
            ),
    );

    if (onTap == null) return avatar;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: avatar,
    );
  }
}
