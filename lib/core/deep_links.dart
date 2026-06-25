class CruiseDeepLinks {
  CruiseDeepLinks._();

  static const host = 'cruiseconnector.at';
  static const baseUrl = 'https://$host';

  static Uri postUri(String postId) {
    return Uri.https(host, '/', {'post': postId});
  }

  /// 2026-06-25 (vucko): Generischer Share-Deeplink fürs externe Teilen einer
  /// Route. Im geteilten Text mitgeschickt → tippt der Empfänger ihn an, öffnet
  /// sich die App (Android App-Link ist im Manifest `autoVerify`); ohne App
  /// landet er auf der Website. (iOS Universal Link braucht zusätzlich die
  /// gehostete apple-app-site-association — reine Infra, kein App-Code.)
  static Uri shareUri({String ref = 'route-share'}) {
    return Uri.https(host, '/', {'ref': ref});
  }

  static String get shareUrl => shareUri().toString();
}
