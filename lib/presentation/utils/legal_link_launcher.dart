import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cruise_connect/core/legal_documents.dart';

Future<bool> launchLegalDocument(LegalDocument document) async {
  try {
    return await launchUrl(document.uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('[LegalLink] ${document.url} konnte nicht geoeffnet werden: $e');
    return false;
  }
}
