import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Wiederverwendbarer Avatar mit Bild-Fallback auf Initiale.
/// Nimmt entweder eine [avatarUrl] oder direkt ein [profile]-Map (z.B. aus
/// `posts.profiles`-Joins).
class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final double radius;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.radius = 20,
    this.backgroundColor,
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
    Color? backgroundColor,
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
    final imageProvider = avatarImageProvider(
      context,
      avatarUrl,
      radius: radius,
    );

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? AppAccentColors.accent,
      foregroundImage: imageProvider,
      child: Text(
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

  static ImageProvider<Object>? avatarImageProvider(
    BuildContext context,
    String? url, {
    required double radius,
  }) {
    return resizedNetworkImageProvider(
      context,
      url,
      width: radius * 2,
      height: radius * 2,
      maxCacheSize: 1024,
    );
  }

  static ImageProvider<Object>? resizedNetworkImageProvider(
    BuildContext context,
    String? url, {
    required double width,
    double? height,
    int minCacheSize = 64,
    int maxCacheSize = 2048,
  }) {
    final normalizedUrl = url?.trim();
    if (normalizedUrl == null || normalizedUrl.isEmpty) return null;

    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final cacheWidth = (width * dpr)
        .ceil()
        .clamp(minCacheSize, maxCacheSize)
        .toInt();
    final cacheHeight = height == null
        ? null
        : (height * dpr).ceil().clamp(minCacheSize, maxCacheSize).toInt();
    return ResizeImage.resizeIfNeeded(
      cacheWidth,
      cacheHeight,
      CachedNetworkImageProvider(normalizedUrl),
    );
  }
}
