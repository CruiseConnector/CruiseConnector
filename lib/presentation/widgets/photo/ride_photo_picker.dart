import 'dart:typed_data';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

/// Wählt ein Foto aus der Galerie (oder Kamera) und lässt den User den
/// Ausschnitt + Zoom FREI wählen — also genau steuern, *was* vom Bild gezeigt
/// wird und *in welchem Ausmaß* (Pan/Zoom + frei wählbares Seitenverhältnis:
/// Original / Quadrat / 4:3 / 16:9). Gibt die zugeschnittenen JPEG-Bytes
/// zurück, oder null bei Abbruch.
///
/// Eine einzige Stelle für das Fahrt-Foto-Handling → Fahrt-Detail,
/// Post-Route-Abschluss und Share-Composer verhalten sich identisch (und das
/// Ergebnis ist überall persistierbar/teilbar).
Future<Uint8List?> pickAndCropRidePhoto(
  BuildContext context, {
  ImageSource source = ImageSource.gallery,
}) async {
  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 2600,
    imageQuality: 95,
  );
  if (picked == null) return null;

  const presets = <CropAspectRatioPreset>[
    CropAspectRatioPreset.original,
    CropAspectRatioPreset.square,
    CropAspectRatioPreset.ratio4x3,
    CropAspectRatioPreset.ratio16x9,
  ];

  final cropped = await ImageCropper().cropImage(
    sourcePath: picked.path,
    maxWidth: 1600,
    maxHeight: 2000,
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 88,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'Foto zuschneiden',
        toolbarColor: const Color(0xFF0B0E14),
        toolbarWidgetColor: Colors.white,
        activeControlsWidgetColor: AppAccentColors.accent,
        backgroundColor: const Color(0xFF0B0E14),
        cropStyle: CropStyle.rectangle,
        lockAspectRatio: false,
        hideBottomControls: false,
        initAspectRatio: CropAspectRatioPreset.original,
        aspectRatioPresets: presets,
      ),
      IOSUiSettings(
        title: 'Foto zuschneiden',
        doneButtonTitle: 'Fertig',
        cancelButtonTitle: 'Abbrechen',
        aspectRatioLockEnabled: false,
        resetAspectRatioEnabled: true,
        rotateButtonsHidden: false,
        rotateClockwiseButtonHidden: false,
        cropStyle: CropStyle.rectangle,
        aspectRatioPresets: presets,
      ),
      WebUiSettings(
        // Crop-Dialog braucht den Context (nur Web); auf Mobile ignoriert.
        // ignore: use_build_context_synchronously
        context: context,
        presentStyle: WebPresentStyle.dialog,
        size: const CropperSize(width: 560, height: 560),
        dragMode: WebDragMode.move,
        viewwMode: WebViewMode.mode_1,
        movable: true,
        zoomable: true,
        cropBoxMovable: true,
        cropBoxResizable: true,
      ),
    ],
  );
  if (cropped == null) return null;
  return cropped.readAsBytes();
}
