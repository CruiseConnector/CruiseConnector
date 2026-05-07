import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/data/services/vehicle_api_service.dart';
import 'package:cruise_connect/presentation/widgets/car_card.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';
import 'package:cruise_connect/presentation/widgets/vehicle_garage_carousel.dart';

enum _ImageCropPreset { avatar, banner, car }

const int _vehicleDescriptionMaxLength =
    AppInputLimits.vehicleDescriptionMaxLength;
const bool _usernameEditingLockedForTest = true;

final List<_CountryOption> _countryOptions = <_CountryOption>[
  _CountryOption('AT', 'AT-AUT'),
  _CountryOption('DE', 'DE-GER'),
  _CountryOption('GB', 'GB-UK'),
  _CountryOption('JP', 'JP-JPN'),
  _CountryOption('KR', 'KR-KOR'),
  _CountryOption('US', 'US-USA'),
  _CountryOption('IT', 'IT-ITA'),
  _CountryOption('FR', 'FR-FRA'),
  _CountryOption('CH', 'CH-SUI'),
  _CountryOption('SE', 'SE-SWE'),
  _CountryOption('ES', 'ES-ESP'),
  _CountryOption('CZ', 'CZ-CZE'),
  _CountryOption('RO', 'RO-ROU'),
  _CountryOption('CN', 'CN-CHN'),
  _CountryOption('IN', 'IN-IND'),
  _CountryOption('NL', 'NL-NED'),
  _CountryOption('RU', 'RU-RUS'),
];

const Map<String, String> _brandCountryCodes = <String, String>{
  'abarth': 'IT',
  'acura': 'JP',
  'alfa romeo': 'IT',
  'alpina': 'DE',
  'alpine': 'FR',
  'aston martin': 'GB',
  'audi': 'DE',
  'bentley': 'GB',
  'bmw': 'DE',
  'bugatti': 'FR',
  'buick': 'US',
  'byd': 'CN',
  'cadillac': 'US',
  'chevrolet': 'US',
  'chrysler': 'US',
  'citroen': 'FR',
  'cupra': 'ES',
  'dacia': 'RO',
  'daewoo': 'KR',
  'daihatsu': 'JP',
  'dodge': 'US',
  'ferrari': 'IT',
  'fiat': 'IT',
  'ford': 'US',
  'genesis': 'KR',
  'gmc': 'US',
  'honda': 'JP',
  'hyundai': 'KR',
  'infiniti': 'JP',
  'isuzu': 'JP',
  'jaguar': 'GB',
  'jeep': 'US',
  'kia': 'KR',
  'koenigsegg': 'SE',
  'lamborghini': 'IT',
  'land rover': 'GB',
  'lexus': 'JP',
  'lincoln': 'US',
  'lotus': 'GB',
  'maserati': 'IT',
  'mazda': 'JP',
  'mclaren': 'GB',
  'mercedes': 'DE',
  'mercedes benz': 'DE',
  'mini': 'GB',
  'mitsubishi': 'JP',
  'nissan': 'JP',
  'opel': 'DE',
  'peugeot': 'FR',
  'polestar': 'SE',
  'porsche': 'DE',
  'ram': 'US',
  'renault': 'FR',
  'rolls royce': 'GB',
  'saab': 'SE',
  'seat': 'ES',
  'skoda': 'CZ',
  'smart': 'DE',
  'subaru': 'JP',
  'suzuki': 'JP',
  'tata': 'IN',
  'tesla': 'US',
  'toyota': 'JP',
  'vauxhall': 'GB',
  'volkswagen': 'DE',
  'volvo': 'SE',
};

class _CountryOption {
  _CountryOption(this.code, this.label);

  final String code;
  final String label;
}

/// Profil-Editor: Banner + Avatar Upload, Username/Bio/Link, Auto-Stammdaten
/// im Ferrari-Verkaufsanzeigen-Stil.
///
/// In der Testversion ist der Username gesperrt, damit Tester eindeutig
/// zuordenbar bleiben. Die Cooldown-Logik bleibt für spätere Builds erhalten.
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _usernameController = TextEditingController();
  final _bioTitleController = TextEditingController();
  final _bioController = TextEditingController();
  final _linkController = TextEditingController();

  // Auto-Stammdaten
  final _carBrandController = TextEditingController();
  final _carNameController = TextEditingController();
  final _vehicleDescriptionController = TextEditingController();
  final _carMileageController = TextEditingController();
  final _carHorsepowerController = TextEditingController();
  final _carTopSpeedController = TextEditingController();
  final _carZeroToHundredController = TextEditingController();
  final _carDrivetrainController = TextEditingController();
  final _carCylindersController = TextEditingController();
  final _carDisplacementController = TextEditingController();
  final _carYearController = TextEditingController();

  String? _avatarUrl;
  String? _bannerUrl;
  String? _carImageUrl;
  String _carCountryCode = 'AT';
  String _vehicleType = 'car';
  List<Map<String, dynamic>> _vehicleDrafts = [];
  int _selectedVehicleIndex = 0;
  bool _carCountryChangedManually = false;
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
    _bioTitleController.dispose();
    _bioController.dispose();
    _linkController.dispose();
    _carBrandController.dispose();
    _carNameController.dispose();
    _vehicleDescriptionController.dispose();
    _carMileageController.dispose();
    _carHorsepowerController.dispose();
    _carTopSpeedController.dispose();
    _carZeroToHundredController.dispose();
    _carDrivetrainController.dispose();
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
        SocialService.getUserVehicles(uid),
      ]);
      final profile = results[0] as Map<String, dynamic>?;
      final usernameCheck =
          results[1] as ({bool canChange, DateTime? nextChange});
      final vehicles = results[2] as List<Map<String, dynamic>>;
      if (!mounted) return;
      setState(() {
        _initialUsername = (profile?['username'] as String?) ?? '';
        _usernameController.text = _initialUsername;
        _bioTitleController.text = (profile?['bio_title'] as String?) ?? '';
        _bioController.text = (profile?['bio'] as String?) ?? '';
        _linkController.text = (profile?['link'] as String?) ?? '';
        _avatarUrl = profile?['avatar_url'] as String?;
        _bannerUrl = profile?['banner_url'] as String?;
        _nextUsernameChange = usernameCheck.canChange
            ? null
            : usernameCheck.nextChange;

        final legacy = SocialService.legacyVehicleFromProfile(profile);
        _vehicleDrafts = vehicles.isNotEmpty
            ? vehicles
                  .map((vehicle) => Map<String, dynamic>.from(vehicle))
                  .toList()
            : [if (legacy != null) Map<String, dynamic>.from(legacy)];
        if (_vehicleDrafts.isEmpty) {
          _vehicleDrafts = [_emptyVehicleDraft()];
        }
        _selectedVehicleIndex = 0;
        _loadVehicleDraftIntoForm(_vehicleDrafts.first);
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
                leading: Icon(
                  Icons.photo_camera,
                  color: AppAccentColors.accent,
                ),
                title: const Text(
                  'Kamera',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(
                  Icons.photo_library,
                  color: AppAccentColors.accent,
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
      if (mounted) {
        final uid = Supabase.instance.client.auth.currentUser?.id;
        if (uid != null) {
          context.read<CommunityProvider>().applyProfilePatch(uid, {
            column: url,
          });
        }
        await _precacheProfileImage(
          url,
          width: maxWidth.toDouble(),
          height: maxHeight.toDouble(),
        );
        onSuccess(url);
      }
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
        maxHeight: 960,
      );
      if (cropped == null) return;

      final bytes = await cropped.readAsBytes();
      final url = await SocialService.uploadUserAsset(
        bucket: 'car_images',
        bytes: bytes,
        fileName: 'vehicle_${_selectedVehicleIndex + 1}.jpg',
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

  Future<void> _precacheProfileImage(
    String url, {
    required double width,
    double? height,
  }) async {
    if (!mounted) return;
    final imageProvider = UserAvatar.resizedNetworkImageProvider(
      context,
      url,
      width: width,
      height: height,
      maxCacheSize: 1600,
    );
    if (imageProvider == null) return;
    try {
      await precacheImage(
        imageProvider,
        context,
      ).timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('[EditProfile] Bild-Precache fehlgeschlagen: $e');
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
      _ImageCropPreset.car => const CropAspectRatio(ratioX: 4, ratioY: 3),
    };
    final initPreset = switch (preset) {
      _ImageCropPreset.avatar => CropAspectRatioPreset.square,
      _ImageCropPreset.banner => CropAspectRatioPreset.ratio16x9,
      _ImageCropPreset.car => CropAspectRatioPreset.ratio4x3,
    };
    final cropStyle = preset == _ImageCropPreset.avatar
        ? CropStyle.circle
        : CropStyle.rectangle;
    final title = switch (preset) {
      _ImageCropPreset.avatar => 'Profilbild zuschneiden',
      _ImageCropPreset.banner => 'Banner zuschneiden',
      _ImageCropPreset.car => 'Fahrzeug-Foto zuschneiden',
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
          activeControlsWidgetColor: AppAccentColors.accent,
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
    if (_usernameEditingLockedForTest) {
      _usernameController.text = _initialUsername;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Username ist in der Testversion gesperrt.'),
            backgroundColor: Color(0xFF1C1F26),
          ),
        );
      }
      return true;
    }
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
                child: Text(
                  'OK',
                  style: TextStyle(color: AppAccentColors.accent),
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
            child: Text(
              'Ja, ändern',
              style: TextStyle(color: AppAccentColors.accent),
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
      _captureCurrentVehicleDraft();
      // 1) Username separat (Cooldown-Tracking)
      final newName = _usernameEditingLockedForTest
          ? _initialUsername
          : _usernameController.text.trim();
      if (!_usernameEditingLockedForTest &&
          newName.isNotEmpty &&
          newName != _initialUsername) {
        await SocialService.updateUsername(newName);
        _initialUsername = newName;
      }
      // 2) Allgemeines Profil
      await SocialService.updateProfile(
        bioTitle: _bioTitleController.text,
        bio: _bioController.text,
        link: _linkController.text,
      );
      // 3) Garage: mehrere Autos/Motorräder. Das erste Fahrzeug wird vom
      // Service zusätzlich in die Legacy-Profile-Spalten gespiegelt.
      await SocialService.saveUserVehicles(_vehicleDrafts);
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (mounted && uid != null) {
        context.read<CommunityProvider>().applyProfilePatch(uid, {
          'username': newName,
          'bio_title': _bioTitleController.text.trim().isEmpty
              ? null
              : _bioTitleController.text.trim(),
          'bio': _bioController.text.trim(),
          'link': _linkController.text.trim(),
          'avatar_url': _avatarUrl,
          'banner_url': _bannerUrl,
          'car_image_url': _vehicleDrafts.isEmpty
              ? _carImageUrl
              : _vehicleDrafts.first['image_url'],
        });
      }
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

  Map<String, dynamic> _emptyVehicleDraft({String type = 'car'}) {
    return {
      'vehicle_type': type,
      'country_code': 'AT',
      'sort_order': _vehicleDrafts.length,
      'is_primary': _vehicleDrafts.isEmpty,
    };
  }

  Map<String, dynamic> _currentVehicleDraft() {
    return {
      'vehicle_type': _vehicleType,
      'brand': _carBrandController.text,
      'model': _carNameController.text,
      'description': _vehicleDescriptionController.text,
      'first_reg': null,
      'mileage': int.tryParse(_carMileageController.text.trim()),
      'horsepower': int.tryParse(_carHorsepowerController.text.trim()),
      'top_speed': int.tryParse(_carTopSpeedController.text.trim()),
      'zero_to_hundred_seconds': _parseDecimalSeconds(
        _carZeroToHundredController.text,
      ),
      'drivetrain': _carDrivetrainController.text,
      'cylinders': int.tryParse(_carCylindersController.text.trim()),
      'displacement': int.tryParse(_carDisplacementController.text.trim()),
      'year': int.tryParse(_carYearController.text.trim()),
      'country_code': _carCountryCode,
      'image_url': _carImageUrl,
      'sort_order': _selectedVehicleIndex,
      'is_primary': _selectedVehicleIndex == 0,
    };
  }

  void _captureCurrentVehicleDraft() {
    if (_vehicleDrafts.isEmpty) {
      _vehicleDrafts = [_currentVehicleDraft()];
      _selectedVehicleIndex = 0;
      return;
    }
    final safeIndex = _selectedVehicleIndex
        .clamp(0, _vehicleDrafts.length - 1)
        .toInt();
    _vehicleDrafts[safeIndex] = _currentVehicleDraft();
  }

  void _loadVehicleDraftIntoForm(Map<String, dynamic> vehicle) {
    _vehicleType = (vehicle['vehicle_type'] as String?) == 'motorcycle'
        ? 'motorcycle'
        : 'car';
    final loadedBrand = (vehicle['brand'] as String?) ?? '';
    _carBrandController.text = loadedBrand;
    _carNameController.text = (vehicle['model'] as String?) ?? '';
    _vehicleDescriptionController.text =
        (vehicle['description'] as String?) ?? '';
    _carMileageController.text = vehicle['mileage']?.toString() ?? '';
    _carHorsepowerController.text = vehicle['horsepower']?.toString() ?? '';
    _carTopSpeedController.text = vehicle['top_speed']?.toString() ?? '';
    _carZeroToHundredController.text =
        vehicle['zero_to_hundred_seconds']?.toString().replaceAll('.', ',') ??
        '';
    _carDrivetrainController.text = (vehicle['drivetrain'] as String?) ?? '';
    _carCylindersController.text = vehicle['cylinders']?.toString() ?? '';
    _carDisplacementController.text = vehicle['displacement']?.toString() ?? '';
    _carYearController.text = vehicle['year']?.toString() ?? '';
    _carImageUrl = vehicle['image_url'] as String?;
    final country = (vehicle['country_code'] as String?)?.trim().toUpperCase();
    final detectedCountry = _countryCodeForBrand(loadedBrand);
    _carCountryCode =
        _countryOptions.any((option) {
          return option.code == country;
        })
        ? country!
        : detectedCountry ?? 'AT';
    _carCountryChangedManually = country != null && country.isNotEmpty;
  }

  void _selectVehicleDraft(int index) {
    if (index < 0 || index >= _vehicleDrafts.length) return;
    if (index == _selectedVehicleIndex) {
      _captureCurrentVehicleDraft();
      return;
    }
    setState(() {
      _captureCurrentVehicleDraft();
      _selectedVehicleIndex = index;
      _loadVehicleDraftIntoForm(_vehicleDrafts[index]);
    });
  }

  void _addVehicleDraft() {
    setState(() {
      _captureCurrentVehicleDraft();
      _vehicleDrafts.add(_emptyVehicleDraft(type: 'car'));
      _selectedVehicleIndex = _vehicleDrafts.length - 1;
      _carCountryChangedManually = false;
      _renumberVehicleDrafts();
      _loadVehicleDraftIntoForm(_vehicleDrafts.last);
    });
  }

  void _renumberVehicleDrafts() {
    for (var i = 0; i < _vehicleDrafts.length; i++) {
      _vehicleDrafts[i]['sort_order'] = i;
      _vehicleDrafts[i]['is_primary'] = i == 0;
    }
  }

  String _vehicleTitleForDraft(Map<String, dynamic> vehicle) {
    final brand = (vehicle['brand'] as String?)?.trim() ?? '';
    final model = (vehicle['model'] as String?)?.trim() ?? '';
    final title = '$brand $model'.trim();
    if (title.isNotEmpty) return title;
    final type = (vehicle['vehicle_type'] as String?) == 'motorcycle'
        ? 'Motorrad'
        : 'Auto';
    return '$type ${_selectedVehicleIndex + 1}';
  }

  Future<void> _deleteSelectedVehicleDraft() async {
    if (_vehicleDrafts.isEmpty) return;
    _captureCurrentVehicleDraft();
    final safeIndex = _selectedVehicleIndex
        .clamp(0, _vehicleDrafts.length - 1)
        .toInt();
    final title = _vehicleTitleForDraft(_vehicleDrafts[safeIndex]);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text(
          'Fahrzeugkarte löschen?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Es wird nur "$title" aus deiner Garage entfernt. Andere Karten bleiben erhalten.',
          style: const TextStyle(color: Colors.white70),
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
              'Löschen',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      if (_vehicleDrafts.length == 1) {
        _vehicleDrafts = [_emptyVehicleDraft()];
        _selectedVehicleIndex = 0;
      } else {
        _vehicleDrafts.removeAt(safeIndex);
        _selectedVehicleIndex = safeIndex
            .clamp(0, _vehicleDrafts.length - 1)
            .toInt();
      }
      _renumberVehicleDrafts();
      _loadVehicleDraftIntoForm(_vehicleDrafts[_selectedVehicleIndex]);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Fahrzeugkarte entfernt. Speichern übernimmt die Änderung.',
        ),
        backgroundColor: Color(0xFF1C1F26),
      ),
    );
  }

  double? _parseDecimalSeconds(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    final parsed = double.tryParse(normalized);
    if (parsed == null) return null;
    return parsed.clamp(0, 99.9).toDouble();
  }

  String? _countryCodeForBrand(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return null;

    final exact = _brandCountryCodes[normalized];
    if (exact != null) return exact;

    for (final entry in _brandCountryCodes.entries) {
      if (normalized.startsWith('${entry.key} ') ||
          normalized.contains(' ${entry.key} ')) {
        return entry.value;
      }
    }
    return null;
  }

  void _handleCarBrandChanged(String value) {
    if (_carCountryChangedManually) return;
    final detected = _countryCodeForBrand(value);
    if (detected == null || detected == _carCountryCode) return;
    setState(() => _carCountryCode = detected);
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
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: AppAccentColors.accent,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    'Speichern',
                    style: TextStyle(
                      color: AppAccentColors.accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: _loading
            ? Center(
                child: CircularProgressIndicator(color: AppAccentColors.accent),
              )
            : ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
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
                        _buildTextField(
                          _usernameController,
                          '@username',
                          maxLength: AppInputLimits.usernameMaxLength,
                          inputFormatters: AppInputLimits.usernameFormatters,
                          enabled: !_usernameEditingLockedForTest,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _usernameEditingLockedForTest
                              ? 'Username ist für die heutige Testversion gesperrt.'
                              : _nextUsernameChange != null
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

                        _buildLabel('Bio-Überschrift'),
                        _buildTextField(
                          _bioTitleController,
                          'z.B. Über mich',
                          maxLength: AppInputLimits.bioTitleMaxLength,
                        ),
                        const SizedBox(height: 20),

                        _buildLabel('Steckbrief / Bio'),
                        _buildTextField(
                          _bioController,
                          'Erzähl etwas über dich…',
                          maxLines: 4,
                          maxLength: AppInputLimits.bioMaxLength,
                        ),
                        // Live-Counter, weil counterText im TextField selbst
                        // ausgeblendet ist (sonst doppelt mit anderen Feldern).
                        Padding(
                          padding: const EdgeInsets.only(top: 4, right: 4),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '${_bioController.text.length}/${AppInputLimits.bioMaxLength}',
                              style: TextStyle(
                                color:
                                    _bioController.text.length >=
                                        AppInputLimits.bioMaxLength
                                    ? AppAccentColors.accent
                                    : Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        _buildLabel('Link / Webseite'),
                        _buildTextField(
                          _linkController,
                          'https://…',
                          maxLength: AppInputLimits.linkMaxLength,
                        ),

                        const SizedBox(height: 32),

                        _buildSectionHeader(
                          'Meine Garage',
                          Icons.garage_rounded,
                        ),
                        const SizedBox(height: 16),
                        _buildCarEditor(),
                      ],
                    ),
                  ),
                ],
              ),
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
                          image: UserAvatar.resizedNetworkImageProvider(
                            context,
                            _bannerUrl,
                            width: MediaQuery.sizeOf(context).width,
                            height: 220,
                            maxCacheSize: 1600,
                          )!,
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
                          color: AppAccentColors.accent,
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
      'vehicle_type': _vehicleType,
      'brand': _carBrandController.text,
      'model': _carNameController.text,
      'description': _vehicleDescriptionController.text,
      'first_reg': null,
      'mileage': int.tryParse(_carMileageController.text.trim()),
      'horsepower': int.tryParse(_carHorsepowerController.text.trim()),
      'top_speed': int.tryParse(_carTopSpeedController.text.trim()),
      'zero_to_hundred_seconds': _parseDecimalSeconds(
        _carZeroToHundredController.text,
      ),
      'drivetrain': _carDrivetrainController.text,
      'cylinders': int.tryParse(_carCylindersController.text.trim()),
      'displacement': int.tryParse(_carDisplacementController.text.trim()),
      'year': int.tryParse(_carYearController.text.trim()),
      'country_code': _carCountryCode,
      'image_url': _carImageUrl,
    };
    final previewVehicles = _vehicleDrafts.isEmpty
        ? [liveProfile]
        : [
            for (var i = 0; i < _vehicleDrafts.length; i++)
              i == _selectedVehicleIndex ? liveProfile : _vehicleDrafts[i],
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VehicleGarageCarousel(
          vehicles: previewVehicles,
          selectedIndex: _selectedVehicleIndex,
          viewportFraction: 1,
          height: _editableGarageCardHeight(context),
          onAddVehicle: _addVehicleDraft,
          onVehicleTap: _selectVehicleDraft,
          onVehicleChanged: _selectVehicleDraft,
          vehicleBuilder: (context, index) {
            if (index == _selectedVehicleIndex) {
              return _buildVehicleEditorCard(
                title: _vehicleTitleForDraft(liveProfile),
                position: _selectedVehicleIndex + 1,
                total: previewVehicles.length,
              );
            }
            return CarCard(
              profile: previewVehicles[index],
              onTap: () => _selectVehicleDraft(index),
            );
          },
        ),
      ],
    );
  }

  double _editableGarageCardHeight(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 370) return 1160;
    return 1080;
  }

  Widget _buildVehicleEditorCard({
    required String title,
    required int position,
    required int total,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF171B23),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppAccentColors.accent.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppAccentColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _vehicleType == 'motorcycle'
                      ? Icons.two_wheeler_rounded
                      : Icons.directions_car_filled_rounded,
                  color: AppAccentColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Karte $position von $total',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Nur diese Fahrzeugkarte löschen',
                child: TextButton.icon(
                  onPressed: _saving ? null : _deleteSelectedVehicleDraft,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text(
                    'Löschen',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildVehiclePhotoEditor(),
          const SizedBox(height: 10),
          _buildVehicleTypeToggle(),
          const SizedBox(height: 10),
          _buildGarageGrid([
            _buildGarageInputTile(
              label: 'Marke',
              icon: Icons.factory_outlined,
              child: _buildMakeField(),
            ),
            _buildGarageInputTile(
              label: 'Modell',
              icon: Icons.badge_outlined,
              child: _buildModelField(),
            ),
          ]),
          const SizedBox(height: 10),
          _buildGarageInputTile(
            label: 'Beschreibung',
            icon: Icons.notes_rounded,
            child: Column(
              children: [
                _buildTextField(
                  _vehicleDescriptionController,
                  'z.B. Tracktool, Daily, Umbau...',
                  maxLines: 3,
                  maxLength: _vehicleDescriptionMaxLength,
                  compact: true,
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${_vehicleDescriptionController.text.length}/$_vehicleDescriptionMaxLength',
                    style: TextStyle(
                      color:
                          _vehicleDescriptionController.text.length >=
                              _vehicleDescriptionMaxLength
                          ? AppAccentColors.accent
                          : Colors.white.withValues(alpha: 0.42),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _buildGarageGrid([
            _buildGarageInputTile(
              label: 'Herkunft',
              icon: Icons.flag_outlined,
              child: _buildCountryDropdown(),
            ),
            _buildGarageInputTile(
              label: 'Baujahr',
              icon: Icons.calendar_today_outlined,
              child: _buildTextField(
                _carYearController,
                '2021',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                compact: true,
              ),
            ),
            _buildGarageInputTile(
              label: 'Antrieb',
              icon: Icons.settings_suggest_outlined,
              child: _buildTextField(
                _carDrivetrainController,
                'Heck / Allrad / Front',
                maxLength: 12,
                compact: true,
              ),
            ),
            _buildGarageInputTile(
              label: 'Kilometer',
              icon: Icons.speed_outlined,
              child: _buildTextField(
                _carMileageController,
                '27870',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                  _MaxIntFormatter(999999),
                ],
                compact: true,
              ),
            ),
            _buildGarageInputTile(
              label: 'Leistung',
              icon: Icons.bolt_rounded,
              child: _buildTextField(
                _carHorsepowerController,
                '720',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                  _MaxIntFormatter(1999),
                ],
                compact: true,
              ),
            ),
            _buildGarageInputTile(
              label: 'Top Speed',
              icon: Icons.keyboard_double_arrow_up_rounded,
              child: _buildTextField(
                _carTopSpeedController,
                '340',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                  _MaxIntFormatter(999),
                ],
                compact: true,
              ),
            ),
            _buildGarageInputTile(
              label: '0-100',
              icon: Icons.timer_outlined,
              child: _buildTextField(
                _carZeroToHundredController,
                '7,3',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  LengthLimitingTextInputFormatter(4),
                  _DecimalSecondsFormatter(),
                ],
                compact: true,
              ),
            ),
            _buildGarageInputTile(
              label: 'Zylinder',
              icon: Icons.adjust_rounded,
              child: _buildTextField(
                _carCylindersController,
                '8',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                  _MaxIntFormatter(24),
                ],
                compact: true,
              ),
            ),
            _buildGarageInputTile(
              label: 'Hubraum',
              icon: Icons.blur_circular_rounded,
              child: _buildTextField(
                _carDisplacementController,
                '3902',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                  _MaxIntFormatter(99999),
                ],
                compact: true,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildVehiclePhotoEditor() {
    final imageUrl = _carImageUrl?.trim();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    return GestureDetector(
      onTap: _uploadingCarImage ? null : _pickCarImage,
      child: Container(
        height: 152,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF0B0E14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasImage)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _vehiclePhotoPlaceholder(),
              )
            else
              _vehiclePhotoPlaceholder(),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.08),
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 14,
              bottom: 14,
              right: 14,
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppAccentColors.accent.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: _uploadingCarImage
                        ? const Padding(
                            padding: EdgeInsets.all(11),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasImage
                          ? 'Fahrzeug-Foto ändern'
                          : 'Fahrzeug-Foto hinzufügen',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vehiclePhotoPlaceholder() {
    return Center(
      child: Icon(
        _vehicleType == 'motorcycle'
            ? Icons.two_wheeler_rounded
            : Icons.directions_car_outlined,
        color: Colors.white.withValues(alpha: 0.18),
        size: 72,
      ),
    );
  }

  Widget _buildGarageGrid(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 300 ? 2 : 1;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }

  Widget _buildGarageInputTile({
    required String label,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppAccentColors.accent),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _buildVehicleTypeToggle() {
    Widget option({
      required String value,
      required IconData icon,
      required String label,
    }) {
      final selected = _vehicleType == value;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _vehicleType = value),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? AppAccentColors.accent
                  : const Color(0xFF1C1F26),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? AppAccentColors.accent
                    : Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 17),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option(value: 'car', icon: Icons.directions_car_filled, label: 'Auto'),
        const SizedBox(width: 10),
        option(
          value: 'motorcycle',
          icon: Icons.two_wheeler_rounded,
          label: 'Motorrad',
        ),
      ],
    );
  }

  Widget _buildCountryDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonFormField<String>(
        key: ValueKey(_carCountryCode),
        initialValue: _carCountryCode,
        isDense: true,
        menuMaxHeight: 280,
        dropdownColor: const Color(0xFF1C1F26),
        iconEnabledColor: AppAccentColors.accent,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: [
          for (final option in _countryOptions)
            DropdownMenuItem<String>(
              value: option.code,
              child: Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) {
          if (value == null) return;
          setState(() {
            _carCountryChangedManually = true;
            _carCountryCode = value;
          });
        },
      ),
    );
  }

  Widget _buildMakeField() {
    return _buildTypeAheadShell<VehicleMake>(
      controller: _carBrandController,
      hint: 'z.B. Toyota',
      suggestionsCallback: VehicleApiService.searchMakes,
      itemTitle: (make) => make.name,
      emptyText: 'Keine Marke gefunden',
      onTextChanged: _handleCarBrandChanged,
      onSelected: (make) {
        _carBrandController.text = make.name;
        _carNameController.clear();
        _carCountryChangedManually = false;
        _handleCarBrandChanged(make.name);
        setState(() {});
      },
    );
  }

  Widget _buildModelField() {
    return _buildTypeAheadShell<VehicleModel>(
      controller: _carNameController,
      hint: 'z.B. Supra',
      suggestionsCallback: (query) {
        return VehicleApiService.searchModels(
          make: _carBrandController.text,
          query: query,
          year: int.tryParse(_carYearController.text.trim()),
        );
      },
      itemTitle: (model) => model.name,
      emptyText: _carBrandController.text.trim().isEmpty
          ? 'Erst Marke wählen'
          : 'Modell manuell eingeben',
      onSelected: (model) {
        _carNameController.text = model.name;
        setState(() {});
      },
    );
  }

  Widget _buildTypeAheadShell<T>({
    required TextEditingController controller,
    required String hint,
    required Future<List<T>> Function(String query) suggestionsCallback,
    required String Function(T item) itemTitle,
    required String emptyText,
    required ValueChanged<T> onSelected,
    ValueChanged<String>? onTextChanged,
  }) {
    return TypeAheadField<T>(
      controller: controller,
      debounceDuration: const Duration(milliseconds: 350),
      retainOnLoading: true,
      constraints: const BoxConstraints(maxHeight: 260),
      decorationBuilder: (context, child) {
        return Material(
          color: const Color(0xFF1C1F26),
          elevation: 10,
          borderRadius: BorderRadius.circular(14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: child,
          ),
        );
      },
      loadingBuilder: (context) => Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppAccentColors.accent,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Lade Fahrzeugdaten...',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
      emptyBuilder: (context) => Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          emptyText,
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
      ),
      errorBuilder: (context, error) => const Padding(
        padding: EdgeInsets.all(14),
        child: Text(
          'API gerade nicht erreichbar. Manuelle Eingabe bleibt möglich.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      ),
      suggestionsCallback: suggestionsCallback,
      itemBuilder: (context, item) {
        return ListTile(
          dense: true,
          title: Text(
            itemTitle(item),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
      onSelected: onSelected,
      builder: (context, fieldController, focusNode) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: fieldController,
            focusNode: focusNode,
            maxLength: AppInputLimits.shortTextMaxLength,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            onChanged: (value) {
              onTextChanged?.call(value);
              setState(() {});
            },
            decoration: InputDecoration(
              counterText: '',
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5)),
              suffixIcon: Icon(
                Icons.search_rounded,
                color: AppAccentColors.accent,
                size: 19,
              ),
              suffixIconConstraints: const BoxConstraints(minWidth: 38),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppAccentColors.accent, size: 22),
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
    ValueChanged<String>? onChanged,
    bool enabled = true,
    bool compact = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFF1C1F26) : const Color(0xFF171B23),
        borderRadius: BorderRadius.circular(12),
        border: enabled
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: TextField(
        enabled: enabled,
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        maxLength: maxLength,
        style: TextStyle(
          color: enabled ? Colors.white : Colors.white54,
          fontSize: compact ? 18 : null,
        ),
        onChanged: (value) {
          onChanged?.call(value);
          setState(() {});
        }, // Live-Vorschau
        decoration: InputDecoration(
          // Counter ausblenden, wenn maxLength gesetzt ist — sonst doppelte
          // Stat-Anzeige unter dem Feld.
          counterText: '',
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5)),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 8 : 12,
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
  _MaxIntFormatter(this.max);

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
class _DecimalSecondsFormatter extends TextInputFormatter {
  _DecimalSecondsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll('.', ',');
    if (text.isEmpty) return newValue.copyWith(text: text);
    if (!RegExp(r'^\d{0,2}(,\d?)?$').hasMatch(text)) return oldValue;
    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed != null && parsed >= 100) return oldValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class MonthYearFormatter extends TextInputFormatter {
  MonthYearFormatter();

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
