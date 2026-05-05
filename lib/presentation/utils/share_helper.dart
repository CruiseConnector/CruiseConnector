import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

Rect? _shareOrigin(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.attached) return null;
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void _showShareError(BuildContext context) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(
    const SnackBar(
      content: Text('Teilen fehlgeschlagen. Bitte erneut versuchen.'),
      backgroundColor: Color(0xFF1C1F26),
    ),
  );
}

Future<void> shareText(
  BuildContext context, {
  required String text,
  String? subject,
}) async {
  try {
    await Share.share(
      text,
      subject: subject,
      sharePositionOrigin: _shareOrigin(context),
    );
  } catch (_) {
    if (context.mounted) _showShareError(context);
  }
}

Future<void> shareFiles(
  BuildContext context,
  List<XFile> files, {
  String? text,
  String? subject,
  List<String>? fileNameOverrides,
}) async {
  try {
    await Share.shareXFiles(
      files,
      text: text,
      subject: subject,
      sharePositionOrigin: _shareOrigin(context),
      fileNameOverrides: fileNameOverrides,
    );
  } catch (_) {
    rethrow;
  }
}
