import 'dart:async';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/auth_service.dart';
import 'package:cruise_connect/data/services/app_tutorial_service.dart';
import 'package:cruise_connect/data/services/map_cache_status.dart';
import 'package:cruise_connect/data/services/map_style_service.dart';
import 'package:cruise_connect/data/services/notification_settings_service.dart';
import 'package:cruise_connect/data/services/offline_map_service.dart';
import 'package:cruise_connect/data/services/poi_settings_service.dart';
import 'package:cruise_connect/data/services/voice_settings_service.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/presentation/pages/welcome_page.dart';
import 'package:cruise_connect/presentation/widgets/accent_color_picker.dart';
import 'package:cruise_connect/presentation/widgets/group_safety_notice_sheet.dart';
import 'package:cruise_connect/presentation/widgets/location_always_notice_sheet.dart';
import 'package:cruise_connect/presentation/widgets/login_options_section.dart';
import 'package:cruise_connect/presentation/widgets/cruise/routing_onboarding_sheet.dart';
import 'package:cruise_connect/presentation/widgets/cruise/voice_volume_sheet.dart';
import 'package:cruise_connect/presentation/widgets/map_download_preference_sheet.dart';
import 'package:cruise_connect/presentation/widgets/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isPrivateAccount = false;
  bool _pushNotifications = true;
  bool _metricUnits = true;
  bool _loading = true;
  bool _deletingAccount = false;
  MapAutoDownloadPolicy _mapAutoDownloadPolicy = MapAutoDownloadPolicy.wifiOnly;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      await MapStyleService.instance.loadAutoDownloadSettings();
      final data = await Supabase.instance.client
          .from('profiles')
          .select('is_private')
          .eq('id', uid)
          .single();
      if (mounted) {
        setState(() {
          _isPrivateAccount = data['is_private'] ?? false;
          _mapAutoDownloadPolicy = MapStyleService.instance.autoDownloadPolicy;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Settings] Privacy laden fehlgeschlagen: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _mapAutoDownloadSubtitle {
    return _mapAutoDownloadPolicy == MapAutoDownloadPolicy.wifiOnly
        ? 'Automatisch nur im WLAN'
        : 'Automatisch auch mit mobilen Daten';
  }

  Future<void> _openMapDownloadPreference() async {
    final selected = await showMapDownloadPreferenceSheet(context, force: true);
    if (!mounted || selected == null) return;
    setState(() => _mapAutoDownloadPolicy = selected);
  }

  Future<void> _togglePrivacy(bool newValue) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: Text(
          newValue ? 'Konto privat machen?' : 'Konto öffentlich machen?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          newValue
              ? 'Wenn dein Konto privat ist, können nur deine Follower deine Posts sehen. '
                    'Deine Posts erscheinen nicht mehr im Entdecken-Bereich für andere User.'
              : 'Wenn dein Konto öffentlich ist, kann jeder deine Posts im Entdecken-Bereich sehen.',
          style: const TextStyle(color: Colors.grey, height: 1.4),
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
              newValue ? 'Privat machen' : 'Öffentlich machen',
              style: TextStyle(
                color: AppAccentColors.accent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    setState(() => _isPrivateAccount = newValue);
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'is_private': newValue})
          .eq('id', uid);
      if (mounted) {
        context.read<CommunityProvider>().applyProfilePatch(uid, {
          'is_private': newValue,
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newValue
                  ? 'Dein Konto ist jetzt privat'
                  : 'Dein Konto ist jetzt öffentlich',
            ),
            backgroundColor: const Color(0xFF1C1F26),
          ),
        );
      }
    } catch (e) {
      debugPrint('[Settings] Privacy-Toggle fehlgeschlagen: $e');
      // Rollback
      if (mounted) {
        setState(() => _isPrivateAccount = !newValue);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Speichern'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteAccount() async {
    if (_deletingAccount) return;

    final warningAccepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text(
          'Konto endgültig löschen?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Dadurch werden dein Profil, deine Routen, Posts, Gruppen-Daten, '
          'Fahrzeuge, Medien und lokale App-Daten entfernt. Diese Aktion kann '
          'nicht rückgängig gemacht werden.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Abbrechen',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Weiter',
              style: TextStyle(
                color: AppAccentColors.accent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (warningAccepted != true || !mounted) return;

    final typedConfirmation = await _showDeleteAccountTypeDialog();
    if (typedConfirmation != true || !mounted) return;

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    var navigatedAway = false;
    setState(() => _deletingAccount = true);
    try {
      await AuthService.deleteCurrentAccount();
      if (!rootNavigator.mounted) return;
      navigatedAway = true;
      rootNavigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomePage()),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      TopToast.show(
        context,
        message: _deleteAccountErrorMessage(e.message),
        icon: Icons.error_outline_rounded,
        isError: true,
        duration: const Duration(seconds: 4),
      );
    } on TimeoutException {
      if (!mounted) return;
      TopToast.show(
        context,
        message: 'Supabase ist gerade nicht erreichbar. Verbindung prüfen.',
        icon: Icons.wifi_off_rounded,
        isError: true,
        duration: const Duration(seconds: 4),
      );
    } catch (e, stack) {
      debugPrint('[Settings] Konto löschen fehlgeschlagen: $e\n$stack');
      if (!mounted) return;
      TopToast.show(
        context,
        message: _deleteAccountErrorMessage(e.toString()),
        icon: Icons.error_outline_rounded,
        isError: true,
        duration: const Duration(seconds: 4),
      );
    } finally {
      if (mounted && !navigatedAway) {
        setState(() => _deletingAccount = false);
      }
    }
  }

  Future<void> _replayAppTutorial() async {
    await AppTutorialService.requestReplay();
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<bool?> _showDeleteAccountTypeDialog() async {
    final controller = TextEditingController();
    try {
      return await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final canDelete = controller.text.trim().toLowerCase() == 'löschen';
            return AlertDialog(
              scrollable: true,
              backgroundColor: const Color(0xFF1C1F26),
              title: const Text(
                'Letzte Bestätigung',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tippe Löschen ein, um dein Konto wirklich komplett zu entfernen.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    cursorColor: AppAccentColors.accent,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Löschen',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF11151D),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppAccentColors.accent),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.of(ctx, rootNavigator: true).pop(false);
                  },
                  child: Text(
                    'Abbrechen',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: canDelete
                      ? () async {
                          FocusManager.instance.primaryFocus?.unfocus();
                          await Future<void>.delayed(
                            const Duration(milliseconds: 80),
                          );
                          if (ctx.mounted) {
                            Navigator.of(ctx, rootNavigator: true).pop(true);
                          }
                        }
                      : null,
                  child: Text(
                    'Konto löschen',
                    style: TextStyle(
                      color: canDelete
                          ? AppAccentColors.accent
                          : Colors.white.withValues(alpha: 0.25),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  String _deleteAccountErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('not_authenticated') || lower.contains('jwt')) {
      return 'Bitte melde dich neu an und versuche es nochmal.';
    }
    if (lower.contains('failed host lookup') ||
        lower.contains('socketexception') ||
        lower.contains('network') ||
        lower.contains('timed out') ||
        lower.contains('timeout')) {
      return 'Supabase ist gerade nicht erreichbar. Verbindung prüfen.';
    }
    if (lower.contains('foreign key') || lower.contains('violates')) {
      return 'Datenbank-Verknüpfung blockiert. Migration bitte nochmal ausführen.';
    }
    if (lower.contains('permission denied') || lower.contains('42501')) {
      return 'RPC-Rechte fehlen. Migration bitte nochmal ausführen.';
    }
    if (lower.contains('delete_current_user')) {
      return 'Account-Loeschfunktion ist noch nicht in Supabase deployed.';
    }
    return 'Konto konnte nicht geloescht werden. Bitte erneut versuchen.';
  }

  @override
  Widget build(BuildContext context) {
    final accentProvider = context.watch<AppAccentProvider>();
    final accent = accentProvider.color;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Einstellungen',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionHeader('KONTO & PRIVATSPHÄRE'),
                _buildSectionContainer([
                  _buildSwitchTile(
                    'Privates Konto',
                    _isPrivateAccount,
                    _togglePrivacy,
                    subtitle: _isPrivateAccount
                        ? 'Nur Follower sehen deine Posts'
                        : 'Jeder kann deine Posts sehen',
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  _buildNavTile('Passwort ändern', Icons.lock_outline),
                ]),

                const SizedBox(height: 24),

                // 2026-06-16 (vucko): Konto-Verknüpfung — ein Account, mehrere
                // Anmeldeoptionen (E-Mail / Apple / Google verbinden).
                const LoginOptionsSection(),

                const SizedBox(height: 24),

                _buildSectionHeader('APP-EINSTELLUNGEN'),
                _buildSectionContainer([
                  ListTile(
                    leading: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: const Text(
                      'Akzentfarbe',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    subtitle: Text(
                      accentProvider.option.label,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                    ),
                    onTap: () => showAccentColorPicker(context),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  _buildSwitchTile(
                    'Push-Benachrichtigungen',
                    _pushNotifications,
                    (val) => setState(() => _pushNotifications = val),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  _buildSwitchTile(
                    'Metrische Einheiten (km)',
                    _metricUnits,
                    (val) => setState(() => _metricUnits = val),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  AnimatedBuilder(
                    animation: VoiceSettingsService.instance,
                    builder: (context, _) => _buildSwitchTile(
                      'Sprach-Navigation (Ansagen)',
                      VoiceSettingsService.instance.isEnabled,
                      (val) {
                        unawaited(
                          VoiceSettingsService.instance.setEnabled(val),
                        );
                        // 2026-06-23 (vucko Voice-Lautstärke): beim Einschalten
                        // das Lautstärke-Sheet mit Test-Stimme zeigen.
                        if (val) unawaited(showVoiceVolumeSheet(context));
                      },
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  _buildNavTile(
                    'Sicherheits- & Routing-Hinweise',
                    Icons.shield_outlined,
                    subtitle:
                        'Haftung, Routenmodi, Wegpunkte und Sicherheit nachlesen',
                    onTap: () =>
                        showRoutingOnboardingSheet(context, force: true),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  _buildNavTile(
                    'Gruppenfahrt-Hinweise',
                    Icons.groups_2_outlined,
                    subtitle:
                        'Keine Veranstaltung, Verantwortung und sichere Gruppenregeln',
                    onTap: () =>
                        showGroupSafetyNoticeSheet(context, force: true),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  _buildNavTile(
                    'Standort im Hintergrund',
                    Icons.location_on_outlined,
                    subtitle:
                        'Warum „Immer erlauben" für aktive Fahrten wichtig ist',
                    onTap: () =>
                        showLocationAlwaysNoticeSheet(context, force: true),
                  ),
                ]),

                const SizedBox(height: 24),

                _buildSectionHeader('POIs AUF DER KARTE'),
                _buildSectionContainer([
                  AnimatedBuilder(
                    animation: PoiSettingsService.instance,
                    builder: (context, _) {
                      final s = PoiSettingsService.instance;
                      return Column(
                        children: [
                          _buildSwitchTile(
                            '⛽  Tankstellen',
                            s.fuel,
                            (v) => s.setFuel(v),
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          _buildSwitchTile(
                            '🍴  Restaurants',
                            s.restaurant,
                            (v) => s.setRestaurant(v),
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          _buildSwitchTile(
                            '☕  Cafés',
                            s.cafe,
                            (v) => s.setCafe(v),
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          _buildSwitchTile(
                            '🔧  Motorrad-Werkstätten',
                            s.repair,
                            (v) => s.setRepair(v),
                          ),
                        ],
                      );
                    },
                  ),
                ]),

                const SizedBox(height: 24),

                _buildSectionHeader('BENACHRICHTIGUNGEN'),
                _buildSectionContainer([
                  AnimatedBuilder(
                    animation: NotificationSettingsService.instance,
                    builder: (context, _) {
                      final s = NotificationSettingsService.instance;
                      return Column(
                        children: [
                          _buildSwitchTile(
                            'Neue Follower',
                            s.follows,
                            (v) => s.setFollows(v),
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          _buildSwitchTile(
                            'Likes auf deine Posts',
                            s.likes,
                            (v) => s.setLikes(v),
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          _buildSwitchTile(
                            'Kommentare',
                            s.comments,
                            (v) => s.setComments(v),
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          _buildSwitchTile(
                            'Freundschaftsanfragen',
                            s.friendRequests,
                            (v) => s.setFriendRequests(v),
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          _buildSwitchTile(
                            'Gruppen-Einladungen',
                            s.groupInvites,
                            (v) => s.setGroupInvites(v),
                          ),
                          const Divider(color: Colors.white10, height: 1),
                          _buildSwitchTile(
                            'Wetter-Tipp morgens (wenn schön)',
                            s.dailyWeather,
                            (v) => s.setDailyWeather(v),
                          ),
                        ],
                      );
                    },
                  ),
                ]),

                const SizedBox(height: 24),

                // 2026-05-28 (vucko Task #64): DACH-Offline-Karte Status +
                // manuelles Re-Download / Cache löschen.
                _buildSectionHeader('OFFLINE-KARTE (DACH)'),
                _buildSectionContainer([
                  _buildNavTile(
                    'Automatischer Download',
                    Icons.cloud_download_outlined,
                    subtitle: _mapAutoDownloadSubtitle,
                    onTap: _openMapDownloadPreference,
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  AnimatedBuilder(
                    animation: MapCacheStatus.instance,
                    builder: (context, _) => _buildOfflineMapCard(),
                  ),
                ]),

                const SizedBox(height: 24),

                _buildSectionHeader('GEFAHRENZONE'),
                _buildSectionContainer([
                  _buildNavTile(
                    'Tutorial nochmal anschauen',
                    Icons.school_outlined,
                    subtitle: 'Home, Community, Cruise, Analytics und Profil',
                    onTap: _replayAppTutorial,
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  ListTile(
                    enabled: !_deletingAccount,
                    leading: _deletingAccount
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AppAccentColors.accent,
                            ),
                          )
                        : Icon(
                            Icons.delete_outline,
                            color: AppAccentColors.accent,
                          ),
                    title: Text(
                      'Konto löschen',
                      style: TextStyle(
                        color: AppAccentColors.accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      _deletingAccount
                          ? 'Account wird geloescht...'
                          : 'Profil, Routen, Posts und Medien entfernen',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    onTap: _deletingAccount ? null : _confirmDeleteAccount,
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildSectionContainer(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F26),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSwitchTile(
    String title,
    bool value,
    Function(bool) onChanged, {
    String? subtitle,
  }) {
    final accent = context.watch<AppAccentProvider>().color;

    return ListTile(
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            )
          : null,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: accent,
        activeTrackColor: accent.withValues(alpha: 0.3),
        inactiveThumbColor: Colors.grey,
        inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildNavTile(
    String title,
    IconData icon, {
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            )
          : null,
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  // 2026-05-28 (vucko Task #64): DACH-Offline-Karte Status-Card.
  // Zeigt den aktuellen Cache-Status (geladen / lädt / fehlgeschlagen /
  // nicht gestartet) mit einem großen Status-Icon, optional Progress-Bar
  // und Action-Buttons (Re-Download bei Fehler, Cache löschen bei OK).
  Widget _buildOfflineMapCard() {
    final status = MapCacheStatus.instance;
    final state = status.state;
    final accent = AppAccentColors.accent;

    Color iconColor;
    IconData iconData;
    String title;
    String subtitle;

    switch (state) {
      case MapCacheState.completed:
        iconColor = const Color(0xFF34D399);
        iconData = Icons.cloud_done_rounded;
        title = 'DACH offline verfügbar';
        subtitle =
            '${status.totalTiles} Tiles · ca. ${status.approxSizeMb} MB · '
            'Tippe „Prüfen" zur Verifikation';
      case MapCacheState.downloading:
        iconColor = accent;
        iconData = Icons.cloud_download_rounded;
        title = 'Karte wird geladen…';
        final pct = (status.progress * 100).toStringAsFixed(0);
        subtitle =
            '$pct% · ${status.downloadedTiles}/${status.totalTiles} Tiles';
      case MapCacheState.failed:
        iconColor = const Color(0xFFF87171);
        iconData = Icons.cloud_off_rounded;
        title = 'Download fehlgeschlagen';
        subtitle = status.lastError ?? 'Unbekannter Fehler';
      case MapCacheState.notStarted:
        iconColor = Colors.grey;
        iconData = Icons.cloud_outlined;
        title = 'DACH noch nicht geladen';
        subtitle = 'Karte (~30 MB) für Offline-Cruising vorbereiten';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Status-Icon + Text
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: iconColor.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(iconData, color: iconColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (state == MapCacheState.downloading) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: status.progress,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (state == MapCacheState.completed) ...[
                Expanded(
                  child: _OfflineMapButton(
                    label: 'Prüfen',
                    icon: Icons.verified_outlined,
                    color: const Color(0xFF34D399),
                    onTap: _verifyAndRepairDachCache,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OfflineMapButton(
                    label: 'Erneut',
                    icon: Icons.refresh_rounded,
                    color: accent,
                    onTap: _redownloadDachCache,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OfflineMapButton(
                    label: 'Löschen',
                    icon: Icons.delete_outline_rounded,
                    color: const Color(0xFFF87171),
                    onTap: _clearDachCache,
                  ),
                ),
              ] else if (state == MapCacheState.downloading) ...[
                Expanded(
                  child: Text(
                    'Bitte App geöffnet lassen…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: _OfflineMapButton(
                    label: state == MapCacheState.failed
                        ? 'Erneut versuchen'
                        : 'Jetzt herunterladen',
                    icon: Icons.cloud_download_rounded,
                    color: accent,
                    onTap: _redownloadDachCache,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _redownloadDachCache() async {
    // 2026-05-28 (vucko): Manuelles Re-Download. Wir setzen das First-
    // Launch-Flag zurück damit der Re-Download als „first install"
    // behandelt wird.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('offline_map_dach_overview_v1');
    if (!mounted) return;
    TopToast.show(
      context,
      message: 'DACH-Karte wird im Hintergrund geladen…',
      icon: Icons.cloud_download_rounded,
      duration: const Duration(seconds: 3),
    );
    unawaited(
      OfflineMapService.instance.cacheDachOverview().then((report) async {
        if (!mounted) return;
        if (report.skipped) return;
        if (report.failedTiles < report.requestedTiles * 0.1) {
          final prefs2 = await SharedPreferences.getInstance();
          await prefs2.setBool('offline_map_dach_overview_v1', true);
          if (!mounted) return;
          TopToast.show(
            context,
            message: 'DACH-Karte ist jetzt offline verfügbar 🗺️',
            icon: Icons.cloud_done_rounded,
            duration: const Duration(seconds: 4),
          );
        }
      }),
    );
  }

  /// 2026-05-28 (vucko Task #69): Verify+Repair manuell aus Settings
  /// triggern. Zeigt Live-Progress + Ergebnis-Toast.
  Future<void> _verifyAndRepairDachCache() async {
    if (!mounted) return;
    TopToast.show(
      context,
      message: 'Karte wird geprüft — fehlende Tiles werden nachgeladen…',
      icon: Icons.verified_outlined,
      duration: const Duration(seconds: 3),
    );
    final result = await OfflineMapService.instance
        .verifyAndRepairDachOverview();
    if (!mounted) return;
    if (result.stillMissing == 0) {
      TopToast.show(
        context,
        message: result.repairedNow > 0
            ? '✅ ${result.repairedNow} Tiles repariert — Karte ist komplett.'
            : '✅ Karte ist komplett (${result.ok} Tiles).',
        icon: Icons.check_circle_outline_rounded,
        duration: const Duration(seconds: 4),
      );
    } else {
      TopToast.show(
        context,
        message:
            '⚠️ ${result.stillMissing} Tiles fehlen weiterhin — Netzverbindung prüfen.',
        icon: Icons.warning_amber_rounded,
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<void> _clearDachCache() async {
    final accent = AppAccentColors.accent;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text(
          'DACH-Cache löschen?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Die Übersichts-Karte muss beim nächsten Cruise-Start neu geladen werden.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Abbrechen',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Löschen',
              style: TextStyle(color: accent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await OfflineMapService.instance.clearDachOverviewCache();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('offline_map_dach_overview_v1');
    if (!mounted) return;
    TopToast.show(
      context,
      message: '$deleted Tiles gelöscht — Cache leer',
      icon: Icons.delete_outline_rounded,
      duration: const Duration(seconds: 3),
    );
  }
}

/// Pillen-Button mit Akzent-Farben für die Offline-Map-Card.
class _OfflineMapButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _OfflineMapButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
          ),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
