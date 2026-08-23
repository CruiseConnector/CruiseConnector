import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/community_chat_service.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/community_chat_detail_page.dart';
import 'package:cruise_connect/presentation/widgets/community_avatar.dart';
import 'package:cruise_connect/presentation/widgets/user_avatar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 2026-08-23 (Auftrag Vucko, Sprachnachricht): „...dass man für Communities
/// wirklich auch Profilbilder reintun kann und auch entweder in den nur
/// Schreibmodus für den Admin einstellen kann oder auch Schreibmodus für alle.
/// Und ganz wichtig, dass man auch im Nachhinein einstellen kann, ob eine
/// Community privat oder öffentlich ist."
///
/// GEMESSEN am 23.08.2026: Schreibmodus und Sichtbarkeit gab es BEREITS und
/// sie funktionierten serverseitig (Spalten `owner_only_messages` und
/// `is_public`, Dienste `setOwnerOnlyMessages` und `setCommunityVisibility`).
/// Sie lagen aber im Drei-Punkte-Menü INNERHALB des Community-Chats,
/// community_chat_detail_page.dart Zeile 963 und 987. Vucko hat sie schlicht
/// nicht gefunden und hielt sie für fehlend. Das ist kein fehlendes Feature,
/// sondern ein Auffindbarkeits-Problem.
///
/// Diese Seite bündelt deshalb ALLES an einer Stelle und ist von BEIDEN Orten
/// erreichbar: aus der Chat-Detailseite und aus dem Karten-Menü der Übersicht.
/// Neu dazugekommen sind nur das Bild sowie Name und Beschreibung, die vorher
/// nach dem Anlegen gar nicht mehr änderbar waren.
class CommunitySettingsPage extends StatefulWidget {
  const CommunitySettingsPage({
    super.key,
    required this.communityId,
    this.initialCommunity,
  });

  final String communityId;

  /// Falls der Aufrufer die Zeile schon hat, spart das ein Aufblitzen.
  final Map<String, dynamic>? initialCommunity;

  @override
  State<CommunitySettingsPage> createState() => _CommunitySettingsPageState();
}

class _CommunitySettingsPageState extends State<CommunitySettingsPage> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  Map<String, dynamic>? _community;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _joinRequests = [];
  String? _inviteCode;

  bool _loading = true;
  bool _savingProfile = false;
  bool _uploadingImage = false;
  bool _busyRequest = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _community = widget.initialCommunity;
    _applyToForm(widget.initialCommunity);
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _applyToForm(Map<String, dynamic>? community) {
    if (community == null) return;
    _nameCtrl.text = community['name']?.toString() ?? '';
    _descCtrl.text = community['description']?.toString() ?? '';
  }

  Future<void> _load() async {
    try {
      final community = await CommunityChatService.fetchCommunity(
        widget.communityId,
      );
      final members = await CommunityChatService.fetchMembers(
        widget.communityId,
      );
      if (!mounted) return;
      setState(() {
        _community = community;
        _members = members;
        _loading = false;
      });
      _applyToForm(community);
      // Code und Anfragen hängen an der Rolle, also erst nach den Mitgliedern.
      unawaited(_loadInviteCode());
      unawaited(_loadJoinRequests());
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(e, fallback: 'Einstellungen konnten nicht geladen werden.');
    }
  }

  Future<void> _loadInviteCode() async {
    final code = await CommunityChatService.inviteCodeFor(widget.communityId);
    if (!mounted) return;
    setState(() => _inviteCode = code);
  }

  Future<void> _loadJoinRequests() async {
    if (!_amAdmin) return;
    final requests = await CommunityChatService.fetchJoinRequests(
      widget.communityId,
    );
    if (!mounted) return;
    setState(() => _joinRequests = requests);
  }

  String? get _myRole {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return null;
    for (final member in _members) {
      if (member['user_id'] == uid) return member['role']?.toString();
    }
    return null;
  }

  bool get _amAdmin => _myRole == 'owner';
  bool get _isPublic => _community?['is_public'] == true;
  bool get _ownerOnlyMessages => _community?['owner_only_messages'] == true;

  // ───────────────────────────────────────────────────────────────────────
  // Bild
  // ───────────────────────────────────────────────────────────────────────

  /// Ablauf abgeschaut von edit_profile_page.dart `_pickAndUpload`, damit sich
  /// das Community-Bild genauso anfühlt wie das Profilbild: Quelle wählen,
  /// zuschneiden, hochladen, vorladen. Der Upload selbst läuft über die
  /// Zwillingsfunktion [SocialService.uploadCommunityAsset]; die bestehende
  /// [SocialService.uploadUserAsset] wird an fünf Stellen benutzt und bleibt
  /// deshalb unangetastet.
  Future<void> _pickAndUploadImage() async {
    final source = await _chooseImageSource();
    if (source == null) return;

    final picker = ImagePicker();
    final XFile? picked;
    try {
      picked = await picker.pickImage(
        source: source,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 85,
      );
    } catch (e) {
      debugPrintCommunity('Bild-Auswahl fehlgeschlagen: $e');
      _showMessage(
        source == ImageSource.camera
            ? CommunityImageRules.keinKameraZugriff
            : CommunityImageRules.keinGalerieZugriff,
        error: true,
      );
      return;
    }
    if (picked == null) return;

    setState(() => _uploadingImage = true);
    final vorherigeUrl = CommunityChatService.avatarUrl(_community);
    try {
      final cropped = await _cropSquare(picked);
      // Abgebrochenes Zuschneiden ist kein Fehler, nur ein Rückzieher.
      if (cropped == null) return;

      final bytes = await cropped.readAsBytes();
      final fehler = CommunityImageRules.fehlerFuer(
        fileName: cropped.path,
        byteLength: bytes.length,
      );
      if (fehler != null) {
        _showMessage(fehler, error: true);
        return;
      }

      final url = await SocialService.uploadCommunityAsset(
        communityId: widget.communityId,
        bytes: bytes,
        fileName: 'community.jpg',
        contentType: 'image/jpeg',
      );
      if (url == null) {
        _showMessage(CommunityImageRules.hochladenFehlgeschlagen, error: true);
        return;
      }

      await CommunityChatService.setCommunityAvatarUrl(
        communityId: widget.communityId,
        avatarUrl: url,
      );
      if (!mounted) return;
      setState(() {
        _community = {...?_community, 'avatar_url': url};
        _changed = true;
      });
      await _precacheImage(url);
      // Der Pfad ist immer derselbe (`<communityId>/community.jpg`, upsert),
      // ein Aufräumen der alten Datei ist deshalb nur nötig, wenn sich der
      // Dateiname doch einmal ändert. Der Cache-Buster in der URL sorgt dafür,
      // dass das neue Bild sofort sichtbar wird.
      if (vorherigeUrl != null &&
          SocialService.storagePathFromPublicUrl(
                SocialService.communityImagesBucket,
                vorherigeUrl,
              ) !=
              SocialService.storagePathFromPublicUrl(
                SocialService.communityImagesBucket,
                url,
              )) {
        unawaited(
          SocialService.deleteCommunityAsset(publicUrl: vorherigeUrl),
        );
      }
      _showMessage('Community-Bild gespeichert.');
    } catch (e) {
      debugPrintCommunity('Bild-Upload fehlgeschlagen: $e');
      _showError(e, fallback: CommunityImageRules.hochladenFehlgeschlagen);
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _removeImage() async {
    final aktuelleUrl = CommunityChatService.avatarUrl(_community);
    if (aktuelleUrl == null) return;
    setState(() => _uploadingImage = true);
    try {
      await CommunityChatService.setCommunityAvatarUrl(
        communityId: widget.communityId,
        avatarUrl: null,
      );
      unawaited(SocialService.deleteCommunityAsset(publicUrl: aktuelleUrl));
      if (!mounted) return;
      setState(() {
        _community = {...?_community, 'avatar_url': null};
        _changed = true;
      });
      _showMessage('Community-Bild entfernt.');
    } catch (e) {
      _showError(e, fallback: 'Bild konnte nicht entfernt werden.');
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<ImageSource?> _chooseImageSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1C1F26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
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
              leading: Icon(Icons.photo_camera, color: AppAccentColors.accent),
              title: const Text(
                'Kamera',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: AppAccentColors.accent),
              title: const Text(
                'Galerie',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<CroppedFile?> _cropSquare(XFile image) {
    return ImageCropper().cropImage(
      sourcePath: image.path,
      maxWidth: 720,
      maxHeight: 720,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 88,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Community-Bild zuschneiden',
          toolbarColor: const Color(0xFF0B0E14),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: AppAccentColors.accent,
          backgroundColor: const Color(0xFF0B0E14),
          cropStyle: CropStyle.rectangle,
          lockAspectRatio: true,
          initAspectRatio: CropAspectRatioPreset.square,
          aspectRatioPresets: const [CropAspectRatioPreset.square],
        ),
        IOSUiSettings(
          title: 'Community-Bild zuschneiden',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          cropStyle: CropStyle.rectangle,
          aspectRatioPresets: const [CropAspectRatioPreset.square],
        ),
      ],
    );
  }

  Future<void> _precacheImage(String url) async {
    if (!mounted) return;
    final provider = UserAvatar.resizedNetworkImageProvider(
      context,
      url,
      width: 96,
      height: 96,
    );
    if (provider == null) return;
    try {
      await precacheImage(
        provider,
        context,
      ).timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrintCommunity('Bild-Vorladen fehlgeschlagen: $e');
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Name und Beschreibung
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _saveProfile() async {
    if (_savingProfile) return;
    setState(() => _savingProfile = true);
    try {
      await CommunityChatService.updateCommunityProfile(
        communityId: widget.communityId,
        name: _nameCtrl.text,
        description: _descCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _community = {
          ...?_community,
          'name': _nameCtrl.text.trim(),
          'description': _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
        };
        _changed = true;
      });
      _showMessage('Gespeichert.');
    } catch (e) {
      _showError(e, fallback: 'Speichern gerade nicht möglich.');
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Schreibmodus und Sichtbarkeit
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _setWriteMode(bool ownerOnly) async {
    final vorher = _ownerOnlyMessages;
    if (vorher == ownerOnly) return;
    setState(() {
      _community = {...?_community, 'owner_only_messages': ownerOnly};
      _changed = true;
    });
    try {
      await CommunityChatService.setOwnerOnlyMessages(
        communityId: widget.communityId,
        enabled: ownerOnly,
      );
      _showMessage(
        ownerOnly
            ? 'Ab jetzt schreiben nur Admins und Moderatoren.'
            : 'Ab jetzt schreiben wieder alle Mitglieder.',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _community = {...?_community, 'owner_only_messages': vorher};
        });
      }
      _showError(e, fallback: 'Einstellung konnte nicht gespeichert werden.');
    }
  }

  /// 2026-08-23 (Auftrag Vucko): Das Umschalten lief bisher OHNE Rückfrage
  /// (community_chat_detail_page.dart Zeile 890). Ein Fehltipp im
  /// Drei-Punkte-Menü machte eine private Community sofort öffentlich, und
  /// öffentliche Communities kann jeder ohne Code betreten. Jetzt gibt es eine
  /// Rückfrage, die auch sagt, was der Wechsel bedeutet.
  Future<void> _setVisibility(bool naechsteIstOeffentlich) async {
    final vorher = _isPublic;
    if (vorher == naechsteIstOeffentlich) return;

    final frage = CommunitySettingsTexte.sichtbarkeitsFrage(
      naechsteIstOeffentlich,
    );
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151821),
        title: Text(
          frage.titel,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          frage.text,
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              frage.knopf,
              style: TextStyle(color: AppAccentColors.accent),
            ),
          ),
        ],
      ),
    );
    if (bestaetigt != true) return;

    setState(() {
      _community = {...?_community, 'is_public': naechsteIstOeffentlich};
      _changed = true;
    });
    try {
      await CommunityChatService.setCommunityVisibility(
        communityId: widget.communityId,
        isPublic: naechsteIstOeffentlich,
      );
      _showMessage(frage.erfolg);
      unawaited(_loadJoinRequests());
    } catch (e) {
      if (mounted) {
        setState(() {
          _community = {...?_community, 'is_public': vorher};
        });
      }
      _showError(e, fallback: 'Sichtbarkeit konnte nicht geändert werden.');
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Beitrittsanfragen
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _answerJoinRequest(String requestId, bool annehmen) async {
    if (_busyRequest) return;
    setState(() => _busyRequest = true);
    try {
      if (annehmen) {
        await CommunityChatService.acceptJoinRequest(requestId);
      } else {
        await CommunityChatService.rejectJoinRequest(requestId);
      }
      if (!mounted) return;
      setState(() {
        _joinRequests = _joinRequests
            .where((request) => request['id']?.toString() != requestId)
            .toList();
        _changed = true;
      });
      _showMessage(annehmen ? 'Angenommen.' : 'Abgelehnt.');
      unawaited(_load());
    } catch (e) {
      _showError(e, fallback: 'Anfrage konnte nicht beantwortet werden.');
    } finally {
      if (mounted) setState(() => _busyRequest = false);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Mitglieder und Löschen
  // ───────────────────────────────────────────────────────────────────────

  void _openMembers() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => CommunityMembersSheet(
        communityId: widget.communityId,
        initialMembers: _members,
        ownerOnlyMessages: _ownerOnlyMessages,
        onChanged: () async {
          _changed = true;
          await _load();
        },
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final loeschen = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151821),
        title: const Text(
          'Community löschen?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Diese Community, alle Mitglieder und Nachrichten werden dauerhaft '
          'gelöscht. Das lässt sich nicht rückgängig machen.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Löschen',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (loeschen != true) return;
    try {
      await CommunityChatService.deleteCommunity(widget.communityId);
      if (!mounted) return;
      Navigator.pop(context, CommunitySettingsResult.deleted);
    } catch (e) {
      _showError(e, fallback: 'Community konnte nicht gelöscht werden.');
    }
  }

  Future<void> _copyInviteCode() async {
    final code = _inviteCode;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    _showMessage('Code kopiert.');
  }

  // ───────────────────────────────────────────────────────────────────────
  // Meldungen
  // ───────────────────────────────────────────────────────────────────────

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: error
            ? const Color(0xFF301B20)
            : const Color(0xFF1C1F26),
      ),
    );
  }

  void _showError(Object error, {required String fallback}) {
    _showMessage(
      CommunitySettingsTexte.lesbarerFehler(error, fallback),
      error: true,
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Aufbau
  // ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(
          context,
          _changed
              ? CommunitySettingsResult.changed
              : CommunitySettingsResult.unchanged,
        );
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0E14),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0E14),
          foregroundColor: Colors.white,
          title: const Text(
            'Community-Einstellungen',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : !_amAdmin
            ? _buildNoAccess()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  _buildImageSection(),
                  const SizedBox(height: 16),
                  _buildProfileSection(),
                  const SizedBox(height: 16),
                  _buildWriteModeSection(),
                  const SizedBox(height: 16),
                  _buildVisibilitySection(),
                  const SizedBox(height: 16),
                  _buildInviteCodeSection(),
                  if (_joinRequests.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildJoinRequestsSection(),
                  ],
                  const SizedBox(height: 16),
                  _buildMembersSection(),
                  const SizedBox(height: 16),
                  _buildDangerSection(),
                ],
              ),
      ),
    );
  }

  /// Die Seite ist nur für Admins. Wer über einen alten Verweis hier landet
  /// (Rolle wurde inzwischen entzogen), bekommt einen ehrlichen Satz statt
  /// leerer Schalter, die beim Tippen an der Regel scheitern.
  Widget _buildNoAccess() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, color: Colors.grey, size: 40),
            SizedBox(height: 14),
            Text(
              CommunitySettingsTexte.keinZugriff,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151821),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildImageSection() {
    final hasImage = CommunityChatService.avatarUrl(_community) != null;
    return _buildCard(
      title: 'Community-Bild',
      subtitle:
          'Das Bild steht auf der Kachel in der Übersicht und oben im Chat. '
          'Erlaubt sind JPG, PNG und WEBP bis 5 MB.',
      children: [
        Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                CommunityAvatar.fromCommunity(
                  _community,
                  size: 76,
                  borderRadius: 18,
                ),
                if (_uploadingImage)
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ElevatedButton.icon(
                    onPressed: _uploadingImage ? null : _pickAndUploadImage,
                    icon: const Icon(Icons.photo_camera, size: 17),
                    label: Text(hasImage ? 'Bild ändern' : 'Bild wählen'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppAccentColors.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (hasImage)
                    TextButton.icon(
                      onPressed: _uploadingImage ? null : _removeImage,
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 17,
                        color: Colors.redAccent,
                      ),
                      label: const Text(
                        'Bild entfernen',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProfileSection() {
    return _buildCard(
      title: 'Name und Beschreibung',
      children: [
        _buildField(
          controller: _nameCtrl,
          label: 'Name',
          maxLength: AppInputLimits.communityNameMaxLength,
        ),
        const SizedBox(height: 12),
        _buildField(
          controller: _descCtrl,
          label: 'Beschreibung',
          maxLength: AppInputLimits.communityDescriptionMaxLength,
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: _savingProfile ? null : _saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppAccentColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(_savingProfile ? 'Speichert...' : 'Speichern'),
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required int maxLength,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        counterStyle: const TextStyle(color: Colors.grey, fontSize: 11),
        filled: true,
        fillColor: const Color(0xFF1C1F26),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  /// Der alte Menütext hieß „Nur Owner schreibt" und war SACHLICH FALSCH:
  /// die Regel `members_write_community_messages` lässt im nur-Admin-Modus
  /// `owner` UND `moderator` durch (am 23.08.2026 in der Produktivdatenbank
  /// nachgelesen). Der Text sagt jetzt, was wirklich passiert, und nennt
  /// zusätzlich Vuckos Entscheidung: gesperrt werden nur Beiträge, das
  /// Reagieren mit Emoji bleibt für alle offen.
  Widget _buildWriteModeSection() {
    return _buildCard(
      title: 'Wer darf schreiben',
      subtitle: CommunityChatService.writeModeExplanation,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _ownerOnlyMessages,
          onChanged: _setWriteMode,
          activeThumbColor: AppAccentColors.accent,
          title: Text(
            _ownerOnlyMessages
                ? CommunityChatService.writeModeAdminsTitle
                : CommunityChatService.writeModeEveryoneTitle,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            _ownerOnlyMessages
                ? 'Mitglieder lesen mit und reagieren, schreiben aber nicht.'
                : 'Jedes Mitglied schreibt Beiträge.',
            style: const TextStyle(color: Colors.grey, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Widget _buildVisibilitySection() {
    return _buildCard(
      title: 'Sichtbarkeit',
      subtitle: CommunitySettingsTexte.sichtbarkeitErklaerung,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _isPublic,
          onChanged: _setVisibility,
          activeThumbColor: AppAccentColors.accent,
          title: Text(
            _isPublic ? 'Öffentlich' : 'Privat',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            _isPublic
                ? 'Steht im Entdecken und jeder kann ohne Code beitreten.'
                : 'Steht nicht im Entdecken. Beitritt nur über den Code.',
            style: const TextStyle(color: Colors.grey, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Widget _buildInviteCodeSection() {
    final code = _inviteCode;
    return _buildCard(
      title: 'Einladungscode',
      subtitle:
          'Nur Mitglieder sehen diesen Code. Bei einer privaten Community '
          'löst er eine Beitrittsanfrage aus statt eines direkten Beitritts.',
      children: [
        InkWell(
          onTap: code == null ? null : _copyInviteCode,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: AppAccentColors.accent.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppAccentColors.accent.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.key, color: AppAccentColors.accent, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    code ?? 'Code wird geladen...',
                    style: TextStyle(
                      color: code == null ? Colors.grey : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (code != null)
                  const Icon(Icons.copy, color: Colors.white70, size: 17),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 2026-08-23: Ohne diese Liste versanden Anfragen. Vorher gab es im ganzen
  /// Repo keine Ansicht für `community_join_requests` (gemessen: 0 Zeilen in
  /// der Tabelle, weil der Weg dorthin gar nicht existierte).
  Widget _buildJoinRequestsSection() {
    return _buildCard(
      title: 'Beitrittsanfragen (${_joinRequests.length})',
      subtitle:
          'Diese Leute möchten dabei sein. Sie kamen über den Einladungscode, '
          'seit die Community privat ist.',
      children: [
        for (final request in _joinRequests) _buildJoinRequestRow(request),
      ],
    );
  }

  Widget _buildJoinRequestRow(Map<String, dynamic> request) {
    final profile = request['profile'] is Map
        ? Map<String, dynamic>.from(request['profile'] as Map)
        : null;
    final name = CommunityChatService.displayName(
      profile,
      fallbackUserId: request['user_id']?.toString(),
    );
    final requestId = request['id']?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          UserAvatar.fromProfile(profile, fallbackName: name, radius: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '@$name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Ablehnen',
            onPressed: _busyRequest || requestId == null
                ? null
                : () => _answerJoinRequest(requestId, false),
            icon: const Icon(Icons.close, color: Colors.redAccent),
          ),
          IconButton(
            tooltip: 'Annehmen',
            onPressed: _busyRequest || requestId == null
                ? null
                : () => _answerJoinRequest(requestId, true),
            icon: Icon(Icons.check, color: AppAccentColors.accent),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersSection() {
    return _buildCard(
      title: 'Mitglieder',
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: _openMembers,
          leading: const Icon(Icons.people_outline, color: Colors.white70),
          title: Text(
            '${_members.length} Mitglieder verwalten',
            style: const TextStyle(color: Colors.white),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            color: Colors.white38,
          ),
        ),
      ],
    );
  }

  Widget _buildDangerSection() {
    return _buildCard(
      title: 'Gefahrenzone',
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: _confirmDelete,
          leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
          title: const Text(
            'Community löschen',
            style: TextStyle(color: Colors.redAccent),
          ),
        ),
      ],
    );
  }
}

/// Ergebnis der Einstellungs-Seite, damit der Aufrufer weiß, ob er neu laden
/// oder die Seite darunter schließen muss.
enum CommunitySettingsResult { unchanged, changed, deleted }

/// Alle festen Texte und Entscheidungen an einem Ort, damit sie OHNE Gerät
/// prüfbar sind. Sie tragen zwei harte Regeln aus dem Repo: keine
/// Gedankenstriche in Nutzertexten und ausgeschriebene Umlaute.
class CommunitySettingsTexte {
  const CommunitySettingsTexte._();

  static const String keinZugriff =
      'Diese Einstellungen kann nur ein Admin der Community ändern.';

  static const String sichtbarkeitErklaerung =
      'Öffentliche Communities stehen für jeden im Entdecken. Private nicht.';

  /// Die Rückfrage vor dem Umschalten. Beim Wechsel auf privat steht
  /// ausdrücklich drin, was mit schon geteilten Links passiert. Das ist
  /// Vuckos Entscheidung vom 23.08.2026 und serverseitig in
  /// `join_community_with_code_v2` umgesetzt.
  static SichtbarkeitsFrage sichtbarkeitsFrage(bool naechsteIstOeffentlich) {
    if (naechsteIstOeffentlich) {
      return const SichtbarkeitsFrage(
        titel: 'Community öffentlich machen?',
        text:
            'Danach steht die Community für jeden im Entdecken und jeder kann '
            'ohne Code beitreten. Offene Beitrittsanfragen brauchst du dann '
            'nicht mehr zu beantworten.',
        knopf: 'Öffentlich machen',
        erfolg: 'Community ist jetzt öffentlich. Jeder kann beitreten.',
      );
    }
    return const SichtbarkeitsFrage(
      titel: 'Community auf privat stellen?',
      text:
          'Danach taucht die Community nicht mehr im Entdecken auf. Wichtig: '
          'ein schon geteilter Einladungscode führt ab dann nicht mehr direkt '
          'hinein, sondern löst eine Beitrittsanfrage bei dir aus, die du '
          'annehmen oder ablehnen kannst. Alle jetzigen Mitglieder bleiben '
          'drin.',
      knopf: 'Auf privat stellen',
      erfolg:
          'Community ist jetzt privat. Alte Links lösen nur noch eine Anfrage aus.',
    );
  }

  /// Wie `_friendlyError` in der Chat-Detailseite, aber mit einem Unterschied:
  /// ein BENANNTER Fehler aus dem Dienst wird durchgelassen. Rohe
  /// Datenbanktexte bleiben draußen.
  static String lesbarerFehler(Object error, String fallback) {
    if (error is CommunityChatServiceException) {
      if (error.code != null) return error.message;
      final message = error.message.trim();
      if (message.isNotEmpty && message.length <= 140 && !_istRauschen(message)) {
        return message;
      }
      return fallback;
    }
    final raw = error.toString().trim();
    if (raw.isEmpty || raw.length > 140 || _istRauschen(raw)) return fallback;
    return raw;
  }

  static bool _istRauschen(String text) {
    final lower = text.toLowerCase();
    return lower.contains('postgrest') ||
        lower.contains('supabase') ||
        lower.contains('row-level') ||
        lower.contains('rls') ||
        lower.contains('policy') ||
        lower.contains('permission') ||
        lower.contains('schema cache') ||
        lower.contains('violates') ||
        lower.contains('duplicate key') ||
        lower.contains('exception');
  }
}

class SichtbarkeitsFrage {
  const SichtbarkeitsFrage({
    required this.titel,
    required this.text,
    required this.knopf,
    required this.erfolg,
  });

  final String titel;
  final String text;
  final String knopf;
  final String erfolg;
}

/// Was beim Community-Bild schiefgehen kann, und was der Nutzer dann liest.
/// Bewusst rein rechnend und ohne Flutter, damit die hässlichen Fälle ohne
/// Gerät prüfbar sind.
class CommunityImageRules {
  const CommunityImageRules._();

  /// Gleiche Grenze wie im Bucket `community_images` (5 MiB, gemessen am
  /// 23.08.2026). Wird sie hier abgefangen, sieht der Nutzer einen Satz statt
  /// eines Storage-Fehlers nach 25 Sekunden Timeout.
  static const int maxBytes = 5 * 1024 * 1024;

  /// Genau die Typen, die der Bucket zulässt.
  static const Set<String> erlaubteEndungen = {'jpg', 'jpeg', 'png', 'webp'};

  static const String zuGross =
      'Das Bild ist zu groß. Bitte wähle eines unter 5 MB.';

  static const String falschesFormat =
      'Dieses Bildformat geht nicht. Erlaubt sind JPG, PNG und WEBP.';

  static const String leer = 'Die Datei ist leer. Bitte wähle ein Bild.';

  static const String hochladenFehlgeschlagen =
      'Hochladen fehlgeschlagen. Prüfe deine Verbindung und versuche es noch einmal.';

  static const String keinKameraZugriff =
      'Kein Kamera-Zugriff. Bitte erlaube ihn in den Einstellungen.';

  static const String keinGalerieZugriff =
      'Kein Galerie-Zugriff. Bitte erlaube ihn in den Einstellungen.';

  /// Liefert null, wenn das Bild in Ordnung ist, sonst den Satz für den Nutzer.
  static String? fehlerFuer({
    required String fileName,
    required int byteLength,
  }) {
    if (byteLength <= 0) return leer;
    if (byteLength > maxBytes) return zuGross;
    final endung = dateiendung(fileName);
    if (endung == null || !erlaubteEndungen.contains(endung)) {
      return falschesFormat;
    }
    return null;
  }

  /// Endung in Kleinbuchstaben, ohne Punkt und ohne Anhängsel wie `?t=123`.
  static String? dateiendung(String fileName) {
    var name = fileName.trim();
    final frage = name.indexOf('?');
    if (frage >= 0) name = name.substring(0, frage);
    final punkt = name.lastIndexOf('.');
    if (punkt < 0 || punkt == name.length - 1) return null;
    final endung = name.substring(punkt + 1).toLowerCase();
    return endung.isEmpty ? null : endung;
  }
}

void debugPrintCommunity(String message) {
  debugPrint('[CommunitySettings] $message');
}
