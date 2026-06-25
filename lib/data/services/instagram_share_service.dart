import 'package:flutter/services.dart';

/// 2026-06-25 (vucko): Übergibt einen TRANSPARENTEN Sticker-PNG direkt an
/// Instagram Stories. Instagram öffnet die Story mit dem Sticker obenauf — der
/// Nutzer macht sein Foto/Selfie als Hintergrund und kann den Sticker IN
/// Instagram frei verschieben/skalieren/drehen (genau das gewünschte Verhalten).
///
/// Plattform-Brücke:
///  • Android: Intent `com.instagram.share.ADD_TO_STORY` mit `interactive_asset_uri`.
///  • iOS: `com.instagram.sharedSticker.stickerImage` auf das Pasteboard +
///    `instagram-stories://share` öffnen.
///
/// Beide Pfade sind fail-safe: ist Instagram nicht installiert (oder lehnt ab),
/// kommt `false` zurück und der Aufrufer fällt auf das normale System-Teilen
/// zurück. So kann hier NICHTS das bestehende Teilen kaputtmachen.
class InstagramShareService {
  InstagramShareService._();

  static const MethodChannel _channel = MethodChannel('cruise/instagram_story');

  /// true = an Instagram Stories übergeben; false = nicht möglich (Fallback nötig).
  static Future<bool> shareStorySticker(
    String stickerPngPath, {
    String appId = '',
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('shareStorySticker', {
        'stickerPath': stickerPngPath,
        'appId': appId,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Ist Instagram installiert / der Stories-Share erreichbar?
  static Future<bool> isAvailable() async {
    try {
      return (await _channel.invokeMethod<bool>('isInstagramAvailable')) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
