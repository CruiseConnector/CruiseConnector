class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.url,
    required this.deepLinkPath,
  });

  final String title;
  final String url;
  final String deepLinkPath;

  Uri get uri => Uri.parse(url);
  Uri get deepLink =>
      Uri(scheme: 'cruiseconnect', host: 'legal', path: deepLinkPath);
}

class LegalDocuments {
  LegalDocuments._();

  static const host = 'cruiseconnector.at';
  static const baseUrl = 'https://$host';

  static const termsVersion = '1.0-draft-2026-06-27';
  static const privacyVersion = '1.0-draft-2026-06-27';
  static const locale = 'de-AT';
  static const fallbackAppVersion = '1.0.4+48';

  static const terms = LegalDocument(
    title: 'AGB / Terms of Service',
    url: '$baseUrl/terms',
    deepLinkPath: '/terms',
  );

  static const privacy = LegalDocument(
    title: 'Datenschutzerklärung',
    url: '$baseUrl/privacy',
    deepLinkPath: '/privacy',
  );

  static const imprint = LegalDocument(
    title: 'Impressum',
    url: '$baseUrl/imprint',
    deepLinkPath: '/imprint',
  );

  static const support = LegalDocument(
    title: 'Support',
    url: '$baseUrl/support',
    deepLinkPath: '/support',
  );

  static const report = LegalDocument(
    title: 'Inhalte melden',
    url: '$baseUrl/report',
    deepLinkPath: '/report',
  );

  static const legalOverview = LegalDocument(
    title: 'Legal-Uebersicht',
    url: '$baseUrl/legal',
    deepLinkPath: '',
  );

  static const communityGuidelines = LegalDocument(
    title: 'Community-Regeln',
    url: '$baseUrl/community-guidelines',
    deepLinkPath: '/community-guidelines',
  );

  static const eventRules = LegalDocument(
    title: 'Event- und Gruppenfahrt-Regeln',
    url: '$baseUrl/event-rules',
    deepLinkPath: '/event-rules',
  );

  static const thirdPartyNotices = LegalDocument(
    title: 'Drittanbieter-Hinweise',
    url: '$baseUrl/third-party-notices',
    deepLinkPath: '/third-party-notices',
  );

  static const settingsDocuments = <LegalDocument>[
    terms,
    privacy,
    imprint,
    support,
    report,
    communityGuidelines,
    eventRules,
    thirdPartyNotices,
  ];

  static LegalDocument? fromLegalDeepLink(Uri uri) {
    if (uri.scheme != 'cruiseconnect' || uri.host != 'legal') return null;
    final path = uri.path.isEmpty ? '/' : uri.path;
    return switch (path) {
      '/' => legalOverview,
      '/terms' => terms,
      '/privacy' => privacy,
      '/imprint' => imprint,
      '/support' => support,
      '/report' => report,
      '/community-guidelines' => communityGuidelines,
      '/event-rules' => eventRules,
      '/third-party-notices' => thirdPartyNotices,
      _ => legalOverview,
    };
  }
}
