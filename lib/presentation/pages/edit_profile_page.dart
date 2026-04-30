import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/widgets/car_card.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';

enum _ImageCropPreset { avatar, banner, car }

/// Profil-Editor: Banner + Avatar Upload, Username/Bio/Link, Auto-Stammdaten
/// im Ferrari-Verkaufsanzeigen-Stil.
///
/// Username-Änderungen sind auf 1x pro 30 Tage limitiert (Service-Layer
/// prüft via `canChangeUsername()`); vor dem Save erscheint ein
/// Bestätigungsdialog mit Hinweis.
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _linkController = TextEditingController();

  // Auto-Stammdaten
  final _carBrandController = TextEditingController();
  final _carNameController = TextEditingController();
  final _carFirstRegController = TextEditingController();
  final _carMileageController = TextEditingController();
  final _carHorsepowerController = TextEditingController();
  final _carTopSpeedController = TextEditingController();
  final _carCylindersController = TextEditingController();
  final _carDisplacementController = TextEditingController();
  final _carYearController = TextEditingController();

  String? _avatarUrl;
  String? _bannerUrl;
  String? _carImageUrl;
  String _initialUsername = '';
  DateTime? _nextUsernameChange;

  bool _loading = true;
  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _uploadingBanner = false;
  bool _uploadingCarImage = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _bioController.dispose();
    _linkController.dispose();
    _carBrandController.dispose();
    _carNameController.dispose();
    _carFirstRegController.dispose();
    _carMileageController.dispose();
    _carHorsepowerController.dispose();
    _carTopSpeedController.dispose();
    _carCylindersController.dispose();
    _carDisplacementController.dispose();
    _carYearController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait([
        SocialService.getUserProfile(uid),
        SocialService.canChangeUsername(),
      ]);
      final profile = results[0] as Map<String, dynamic>?;
      final usernameCheck =
          results[1] as ({bool canChange, DateTime? nextChange});
      if (!mounted) return;
      setState(() {
        _initialUsername = (profile?['username'] as String?) ?? '';
        _usernameController.text = _initialUsername;
        _bioController.text = (profile?['bio'] as String?) ?? '';
        _linkController.text = (profile?['link'] as String?) ?? '';
        _avatarUrl = profile?['avatar_url'] as String?;
        _bannerUrl = profile?['banner_url'] as String?;
        _nextUsernameChange = usernameCheck.canChange
            ? null
            : usernameCheck.nextChange;

        _carBrandController.text = (profile?['car_brand'] as String?) ?? '';
        _carNameController.text = (profile?['car_name'] as String?) ?? '';
        _carFirstRegController.text =
            (profile?['car_first_reg'] as String?) ?? '';
        _carMileageController.text = profile?['car_mileage']?.toString() ?? '';
        _carHorsepowerController.text =
            profile?['car_horsepower']?.toString() ?? '';
        _carTopSpeedController.text =
            profile?['car_top_speed']?.toString() ?? '';
        _carCylindersController.text =
            profile?['car_cylinders']?.toString() ?? '';
        _carDisplacementController.text =
            profile?['car_displacement']?.toString() ?? '';
        _carYearController.text = profile?['car_year']?.toString() ?? '';
        _carImageUrl = profile?['car_image_url'] as String?;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[EditProfile] Laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<ImageSource?> _chooseImageSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1C1F26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_camera,
                  color: Color(0xFFFF3B30),
                ),
                title: const Text(
                  'Kamera',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: Color(0xFFFF3B30),
                ),
                title: const Text(
                  'Galerie',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUpload({
    required String bucket,
    required String column,
    required int maxWidth,
    required int maxHeight,
    required _ImageCropPreset cropPreset,
    required void Function(bool busy) onBusy,
    required void Function(String url) onSuccess,
  }) async {
    final source = await _chooseImageSource();
    if (source == null) return;

    final picker = ImagePicker();
    final XFile? image;
    try {
      image = await picker.pickImage(
        source: source,
        maxWidth: maxWidth.toDouble(),
        maxHeight: maxHeight.toDouble(),
        imageQuality: 80,
      );
    } catch (e) {
      debugPrint('[EditProfile] Bild-Auswahl fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              source == ImageSource.camera
                  ? 'Kein Kamera-Zugriff. Berechtigung in den Einstellungen erlauben.'
                  : 'Kein Galerie-Zugriff. Berechtigung in den Einstellungen erlauben.',
            ),
            backgroundColor: const Color(0xFF1C1F26),
          ),
        );
      }
      return;
    }
    if (image == null) return;

    onBusy(true);
    try {
      final cropped = await _cropImage(
        image,
        preset: cropPreset,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
      if (cropped == null) return;

      final bytes = await cropped.readAsBytes();
      final fileName = '${column.replaceAll('_url', '')}.jpg';
      final url = await SocialService.uploadUserAsset(
        bucket: bucket,
        bytes: bytes,
        fileName: fileName,
        contentType: 'image/jpeg',
      );
      if (url == null) throw Exception('Upload fehlgeschlagen');
      await SocialService.updateProfileImageUrl(column: column, publicUrl: url);
      if (mounted) onSuccess(url);
    } catch (e) {
      debugPrint('[EditProfile] Upload fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload fehlgeschlagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      onBusy(false);
    }
  }

  Future<void> _pickCarImage() async {
    final source = await _chooseImageSource();
    if (source == null) return;
    final picker = ImagePicker();
    final XFile? image;
    try {
      image = await picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
    } catch (e) {
      debugPrint('[EditProfile] Auto-Bild Auswahl fehlgeschlagen: $e');
      return;
    }
    if (image == null) return;

    setState(() => _uploadingCarImage = true);
    try {
      final cropped = await _cropImage(
        image,
        preset: _ImageCropPreset.car,
        maxWidth: 1280,
        maxHeight: 720,
      );
      if (cropped == null) return;

      final bytes = await cropped.readAsBytes();
      final url = await SocialService.uploadUserAsset(
        bucket: 'car_images',
        bytes: bytes,
        fileName: 'car.jpg',
        contentType: 'image/jpeg',
      );
      if (url == null) throw Exception('Upload fehlgeschlagen');
      if (mounted) setState(() => _carImageUrl = url);
    } catch (e) {
      debugPrint('[EditProfile] Auto-Bild Upload fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _uploadingCarImage = false);
    }
  }

  Future<CroppedFile?> _cropImage(
    XFile image, {
    required _ImageCropPreset preset,
    required int maxWidth,
    required int maxHeight,
  }) {
    final aspectRatio = switch (preset) {
      _ImageCropPreset.avatar => const CropAspectRatio(ratioX: 1, ratioY: 1),
      _ImageCropPreset.banner => const CropAspectRatio(ratioX: 8, ratioY: 3),
      _ImageCropPreset.car => const CropAspectRatio(ratioX: 16, ratioY: 9),
    };
    final initPreset = switch (preset) {
      _ImageCropPreset.avatar => CropAspectRatioPreset.square,
      _ImageCropPreset.banner => CropAspectRatioPreset.ratio16x9,
      _ImageCropPreset.car => CropAspectRatioPreset.ratio16x9,
    };
    final cropStyle = preset == _ImageCropPreset.avatar
        ? CropStyle.circle
        : CropStyle.rectangle;
    final title = switch (preset) {
      _ImageCropPreset.avatar => 'Profilbild zuschneiden',
      _ImageCropPreset.banner => 'Banner zuschneiden',
      _ImageCropPreset.car => 'Auto-Foto zuschneiden',
    };

    return ImageCropper().cropImage(
      sourcePath: image.path,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 88,
      aspectRatio: aspectRatio,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: title,
          toolbarColor: const Color(0xFF0B0E14),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFFFF3B30),
          backgroundColor: const Color(0xFF0B0E14),
          cropStyle: cropStyle,
          lockAspectRatio: true,
          hideBottomControls: false,
          initAspectRatio: initPreset,
          aspectRatioPresets: [initPreset],
        ),
        IOSUiSettings(
          title: title,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          rotateButtonsHidden: false,
          rotateClockwiseButtonHidden: false,
          cropStyle: cropStyle,
          aspectRatioPresets: [initPreset],
        ),
        WebUiSettings(
          context: context,
          presentStyle: WebPresentStyle.dialog,
          size: const CropperSize(width: 520, height: 520),
          dragMode: WebDragMode.move,
          viewwMode: WebViewMode.mode_1,
          movable: true,
          zoomable: true,
          cropBoxMovable: true,
          cropBoxResizable: false,
        ),
      ],
    );
  }

  /// Vor dem Speichern: prüft, ob der Username geändert wurde und triggert
  /// einen Confirmation-Dialog. Returnt false → Save abbrechen.
  Future<bool> _confirmUsernameChangeIfNeeded() async {
    final newName = _usernameController.text.trim();
    if (newName.isEmpty || newName == _initialUsername) return true;
    if (_nextUsernameChange != null) {
      // Cooldown läuft noch — nicht ändern lassen.
      final dt = _nextUsernameChange!;
      final formatted =
          '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C1F26),
            title: const Text(
              'Username noch gesperrt',
              style: TextStyle(color: Colors.white),
            ),
            content: Text(
              'Du hast deinen Benutzernamen kürzlich geändert. Du kannst ihn '
              'erst wieder ab dem $formatted ändern.',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'OK',
                  style: TextStyle(color: Color(0xFFFF3B30)),
                ),
              ),
            ],
          ),
        );
      }
      // Username-Feld zurücksetzen, damit der Save trotzdem für die
      // anderen Felder durchgehen kann.
      _usernameController.text = _initialUsername;
      return true;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text(
          'Username ändern?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Bist du sicher, dass du deinen Benutzernamen ändern möchtest?\n\n'
          'Du kannst deinen Benutzernamen nur einmal pro Monat ändern.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Abbrechen',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Ja, ändern',
              style: TextStyle(color: Color(0xFFFF3B30)),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _save() async {
    if (_saving) return;
    final proceed = await _confirmUsernameChangeIfNeeded();
    if (!proceed) return;

    setState(() => _saving = true);
    try {
      // 1) Username separat (Cooldown-Tracking)
      final newName = _usernameController.text.trim();
      if (newName.isNotEmpty && newName != _initialUsername) {
        await SocialService.updateUsername(newName);
        _initialUsername = newName;
      }
      // 2) Allgemeines Profil
      await SocialService.updateProfile(
        bio: _bioController.text,
        link: _linkController.text,
      );
      // 3) Auto-Stammdaten — leere Strings → werden NICHT als 0 geschrieben,
      //    weil int.tryParse(...) auf '' null returnt.
      await SocialService.updateCarProfile(
        brand: _carBrandController.text,
        name: _carNameController.text,
        firstReg: _carFirstRegController.text,
        mileage: int.tryParse(_carMileageController.text.trim()),
        horsepower: int.tryParse(_carHorsepowerController.text.trim()),
        topSpeed: int.tryParse(_carTopSpeedController.text.trim()),
        cylinders: int.tryParse(_carCylindersController.text.trim()),
        displacement: int.tryParse(_carDisplacementController.text.trim()),
        year: int.tryParse(_carYearController.text.trim()),
        imageUrl: _carImageUrl,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[EditProfile] Speichern fehlgeschlagen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Speichern fehlgeschlagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profil bearbeiten',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Color(0xFFFF3B30),
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Speichern',
                    style: TextStyle(
                      color: Color(0xFFFF3B30),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF3B30)),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _buildBannerWithAvatar(),
                const SizedBox(height: 56),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Username'),
                      _buildTextField(_usernameController, '@username'),
                      const SizedBox(height: 6),
                      Text(
                        _nextUsernameChange != null
                            ? 'Du kannst deinen Benutzernamen erst wieder ab dem '
                                  '${_nextUsernameChange!.day.toString().padLeft(2, '0')}.'
                                  '${_nextUsernameChange!.month.toString().padLeft(2, '0')}.'
                                  '${_nextUsernameChange!.year} ändern.'
                            : 'Du kannst deinen Benutzernamen nur einmal pro Monat ändern.',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),

                      const SizedBox(height: 20),

                      _buildLabel('Steckbrief / Bio'),
                      _buildTextField(
                        _bioController,
                        'Erzähl etwas über dich…',
                        maxLines: 4,
                        maxLength: 500,
                      ),
                      // Live-Counter, weil counterText im TextField selbst
                      // ausgeblendet ist (sonst doppelt mit anderen Feldern).
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 4),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${_bioController.text.length}/500',
                            style: TextStyle(
                              color: _bioController.text.length >= 500
                                  ? const Color(0xFFFF3B30)
                                  : Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      _buildLabel('Link / Webseite'),
                      _buildTextField(_linkController, 'https://…'),

                      const SizedBox(height: 32),

                      _buildSectionHeader(
                        'Mein Auto',
                        Icons.directions_car_filled,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Stammdaten zu deinem Auto. Felder die du leer lässt erscheinen nicht auf der Karte.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      _buildCarEditor(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBannerWithAvatar() {
    return SizedBox(
      height: 220,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            bottom: 50,
            child: GestureDetector(
              onTap: _uploadingBanner
                  ? null
                  : () => _pickAndUpload(
                      bucket: 'banners',
                      column: 'banner_url',
                      maxWidth: 1600,
                      maxHeight: 600,
                      cropPreset: _ImageCropPreset.banner,
                      onBusy: (b) => setState(() => _uploadingBanner = b),
                      onSuccess: (url) => setState(() => _bannerUrl = url),
                    ),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1F26),
                  image: _bannerUrl != null && _bannerUrl!.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(_bannerUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: Stack(
                  children: [
                    if (_bannerUrl == null || _bannerUrl!.isEmpty)
                      Center(
                        child: Icon(
                          Icons.image_outlined,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: _uploadingBanner
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 16,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            bottom: 0,
            child: GestureDetector(
              onTap: _uploadingAvatar
                  ? null
                  : () => _pickAndUpload(
                      bucket: 'avatars',
                      column: 'avatar_url',
                      maxWidth: 512,
                      maxHeight: 512,
                      cropPreset: _ImageCropPreset.avatar,
                      onBusy: (b) => setState(() => _uploadingAvatar = b),
                      onSuccess: (url) => setState(() => _avatarUrl = url),
                    ),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFF0B0E14),
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  children: [
                    UserAvatar(
                      name: _usernameController.text,
                      avatarUrl: _avatarUrl,
                      radius: 50,
                    ),
                    if (_uploadingAvatar)
                      const Positioned.fill(
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.black54,
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF0B0E14),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarEditor() {
    final liveProfile = <String, dynamic>{
      'car_brand': _carBrandController.text,
      'car_name': _carNameController.text,
      'car_first_reg': _carFirstRegController.text,
      'car_mileage': int.tryParse(_carMileageController.text.trim()),
      'car_horsepower': int.tryParse(_carHorsepowerController.text.trim()),
      'car_top_speed': int.tryParse(_carTopSpeedController.text.trim()),
      'car_cylinders': int.tryParse(_carCylindersController.text.trim()),
      'car_displacement': int.tryParse(_carDisplacementController.text.trim()),
      'car_year': int.tryParse(_carYearController.text.trim()),
      'car_image_url': _carImageUrl,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Live-Vorschau
        Center(
          child: SizedBox(width: 320, child: CarCard(profile: liveProfile)),
        ),
        const SizedBox(height: 20),

        // Foto-Upload
        GestureDetector(
          onTap: _uploadingCarImage ? null : _pickCarImage,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1F26),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_uploadingCarImage)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFF3B30),
                    ),
                  )
                else
                  const Icon(
                    Icons.camera_alt,
                    color: Color(0xFFFF3B30),
                    size: 18,
                  ),
                const SizedBox(width: 8),
                Text(
                  _carImageUrl != null && _carImageUrl!.isNotEmpty
                      ? 'Foto ändern'
                      : 'Auto-Foto hinzufügen',
                  style: const TextStyle(
                    color: Color(0xFFFF3B30),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Marke'),
                  _buildTextField(
                    _carBrandController,
                    'z.B. Ferrari',
                    maxLength: 25,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Modell'),
                  _buildTextField(
                    _carNameController,
                    'z.B. F8 Spider',
                    maxLength: 25,
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Erstzulassung'),
                  _buildTextField(
                    _carFirstRegController,
                    'MM/JJJJ',
                    keyboardType: TextInputType.number,
                    inputFormatters: const [_MonthYearFormatter()],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Baujahr'),
                  _buildTextField(
                    _carYearController,
                    '2021',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Kilometerstand'),
                  _buildTextField(
                    _carMileageController,
                    '27870',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                      const _MaxIntFormatter(999999),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Leistung (PS)'),
                  _buildTextField(
                    _carHorsepowerController,
                    '720',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                      const _MaxIntFormatter(1999),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Top Speed (km/h)'),
                  _buildTextField(
                    _carTopSpeedController,
                    '340',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                      const _MaxIntFormatter(999),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Zylinder'),
                  _buildTextField(
                    _carCylindersController,
                    '8',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                      const _MaxIntFormatter(24),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        _buildLabel('Hubraum (cm³)'),
        _buildTextField(
          _carDisplacementController,
          '3902',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
            const _MaxIntFormatter(99999),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFF3B30), size: 22),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        maxLength: maxLength,
        style: const TextStyle(color: Colors.white),
        onChanged: (_) => setState(() {}), // Live-Vorschau
        decoration: InputDecoration(
          // Counter ausblenden, wenn maxLength gesetzt ist — sonst doppelte
          // Stat-Anzeige unter dem Feld.
          counterText: '',
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}

/// Begrenzt die Eingabe auf einen ganzzahligen Maximalwert. Längen-Limit
/// wird zusätzlich via [LengthLimitingTextInputFormatter] gesetzt.
class _MaxIntFormatter extends TextInputFormatter {
  final int max;
  const _MaxIntFormatter(this.max);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final v = int.tryParse(newValue.text);
    if (v == null) return oldValue;
    if (v > max) return oldValue;
    return newValue;
  }
}

/// Formatiert die Eingabe als `MM/JJJJ`. Nimmt nur Ziffern an, fügt das `/`
/// nach den ersten zwei automatisch ein, deckelt bei 6 Ziffern (= 7 Zeichen
/// inkl. `/`). Verhindert auch unmögliche Monate (>12) und führt dabei
/// trotzdem die Eingabe sinnvoll fort.
class _MonthYearFormatter extends TextInputFormatter {
  const _MonthYearFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 6) digits = digits.substring(0, 6);

    // Monat-Validierung: erste Ziffer max 1, zweite Ziffer abhängig.
    if (digits.isNotEmpty) {
      final first = int.parse(digits[0]);
      if (first > 1) digits = '0$digits';
      if (digits.length > 6) digits = digits.substring(0, 6);
    }
    if (digits.length >= 2) {
      final mm = int.parse(digits.substring(0, 2));
      if (mm == 0) {
        digits = '01${digits.substring(2)}';
      } else if (mm > 12) {
        digits = '12${digits.substring(2)}';
      }
    }

    final formatted = digits.length <= 2
        ? digits
        : '${digits.substring(0, 2)}/${digits.substring(2)}';

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
