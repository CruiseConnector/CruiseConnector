import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:cruise_connect/presentation/widgets/photo/ride_photo_picker.dart';
// XFile (PNG-Share-Export) — kam zuvor über image_picker; share_plus
// re-exportiert XFile und ist die passende direkte Dependency dafür.
import 'package:share_plus/share_plus.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/completion_title_generator.dart';
import 'package:cruise_connect/domain/models/badge.dart' as app;
import 'package:flutter/rendering.dart';
import 'package:cruise_connect/presentation/utils/share_helper.dart';

Future<T?> showCruiseCompletionSheet<T>({
  required BuildContext context,
  required CruiseCompletionDialog child,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Cruise completion',
    barrierColor: Colors.black.withValues(alpha: 0.14),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(color: Colors.black.withValues(alpha: 0.08)),
              ),
            ),
            SafeArea(
              top: false,
              child: Align(alignment: Alignment.bottomCenter, child: child),
            ),
          ],
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, dialogChild) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.18),
            end: Offset.zero,
          ).animate(curved),
          child: dialogChild,
        ),
      );
    },
  );
}

class CruiseCompletionActionResult {
  CruiseCompletionActionResult({
    this.success = true,
    this.newBadges = const [],
    this.levelUp = false,
    this.newLevel,
    this.previousTotalXp,
    this.newTotalXp,
    this.xpEarned,
    this.savedRouteId,
  });

  final bool success;
  final List<app.Badge> newBadges;
  final bool levelUp;
  final int? newLevel;
  final int? previousTotalXp;
  final int? newTotalXp;
  final int? xpEarned;

  /// ID der gerade gespeicherten Route — Voraussetzung fürs Veröffentlichen
  /// direkt aus dem Abschluss-Sheet heraus (2026-08-03, vucko).
  final String? savedRouteId;

  bool get hasXpProgress =>
      previousTotalXp != null &&
      newTotalXp != null &&
      newTotalXp! > previousTotalXp!;

  bool get hasCelebration => newBadges.isNotEmpty || levelUp || hasXpProgress;
}

class CruiseCompletionDialog extends StatefulWidget {
  const CruiseCompletionDialog({
    super.key,
    required this.distanceKm,
    required this.durationText,
    required this.curves,
    required this.xpEarned,
    required this.routeCoordinates,
    required this.onSave,
    required this.onDiscard,
    this.routeSegments,
    this.drivenSegments,
    this.baseXp,
    this.streakDays = 1,
    this.xpMultiplier = 1.0,
    this.isEarlyStop = false,
    this.belowMinimum = false,
    this.routeStyle = '',
    this.isRoundTrip = true,
    this.topSpeedKmh = 0,
    this.avgSpeedKmh = 0,
    this.canPublish = false,
    this.folgeVorschlaege = false,
    this.onGruppeErstellen,
  });

  final double distanceKm;
  final String durationText;
  final int curves;
  final int xpEarned;
  // 2026-06-23 (vucko Post-Route Top-Speed): höchstes + Ø-Tempo der Fahrt (km/h).
  final double topSpeedKmh;
  final double avgSpeedKmh;
  // 2026-05-31 (vucko): Für den automatisch generierten, passenden Titel
  // (Wochentag + Tageszeit + Fahrstil) im Header.
  final String routeStyle;
  final bool isRoundTrip;
  final List<List<double>> routeCoordinates;
  final List<List<List<double>>>? routeSegments;

  /// 2026-05-24 (vucko Task #41): GPS-Track der ECHT gefahren wurde.
  /// Wenn vorhanden, wird er als accent-Overlay über die geplante Route
  /// (grau) gezeichnet → "Das bin ich wirklich gefahren".
  final List<List<List<double>>>? drivenSegments;
  final int? baseXp;
  final int streakDays;
  final double xpMultiplier;
  /// 2026-08-04 (vucko „wenn man Speichern oder Verwerfen klickt, dauert es
  /// 15-20 Sekunden, bis reagiert wird"): Der Rückruf gibt NICHTS mehr zurück
  /// und wird NICHT mehr abgewartet. Das Sheet schließt sofort; die Seite
  /// darunter erledigt Foto-Upload, Speichern und XP im Hintergrund und zeigt
  /// die Level-/Badge-Feier dann dort.
  ///
  /// Deshalb wandern auch die Foto-BYTES hinaus statt einer fertigen URL: Der
  /// Upload (bis zu drei Versuche à 25 s) war der längste einzelne Block vor
  /// dem Speichern und hat hier nichts mehr verloren.
  final void Function(
    int? rating,
    List<String> tags,
    String? title,
    Uint8List? photoBytes,
    bool publish,
  )
  onSave;
  final void Function() onDiscard;
  final bool isEarlyStop;
  final bool belowMinimum;

  /// 2026-08-03 (vucko Route-Aufzeichnen): Ist das gesetzt, erscheint
  /// zusätzlich „Speichern & veröffentlichen" — die Strecke wird gespeichert
  /// und danach als Community-Post angeboten. Nur für selbst aufgezeichnete
  /// Strecken; sonst existiert der Knopf gar nicht.
  final bool canPublish;

  /// Zeigt nach der Fahrt zwei dezente Vorschlaege: gemeinsam fahren und
  /// in der Community teilen.
  ///
  /// 2026-08-11 (vucko „vorallem moechte ich, dass die Leute eher sehen, dass
  /// es auch das Gruppenfeature oder das Community-Feature gibt"): Der Moment
  /// direkt nach einer Fahrt ist der beste — da ist jemand stolz auf seine
  /// Strecke. Bewusst als leise Vorschlagszeile und nicht als Dialog: Wer sie
  /// nicht will, uebersieht sie einfach.
  final bool folgeVorschlaege;

  /// Wird gerufen, wenn der Nutzer „Naechstes Mal zu zweit" waehlt.
  final VoidCallback? onGruppeErstellen;

  @override
  State<CruiseCompletionDialog> createState() => _CruiseCompletionDialogState();
}

class _CruiseCompletionDialogState extends State<CruiseCompletionDialog>
    with TickerProviderStateMixin {
  final GlobalKey _shareCardKey = GlobalKey();
  late final AnimationController _xpController;
  late final Animation<int> _xpAnimation;
  bool _isExportMode = false;
  bool _isSharing = false;
  /// 2026-08-04: Ersetzt das frühere `_isSaving`. Da das Sheet jetzt sofort
  /// schließt, gibt es keinen „Speichert..."-Zustand mehr — es braucht nur noch
  /// einen Schutz gegen den zweiten Tap in derselben Millisekunde.
  bool _abgeschickt = false;
  bool _showRatingDetails = false;
  int _selectedRating = 0;
  final Set<String> _selectedTags = <String>{};
  // 2026-05-31 (vucko): Editierbarer Auto-Titel + optionales Foto fürs Teilen.
  late final TextEditingController _titleController;
  /// 2026-08-04: Nur noch die BYTES. Hochgeladen wird im Hintergrund auf der
  /// Cruise-Seite, nicht mehr hier — der Upload (bis zu 3 Versuche à 25 s) war
  /// der längste einzelne Block vor dem Speichern.
  Uint8List? _photoBytes;
  bool _isPickingPhoto = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: CompletionTitleGenerator.generate(
        time: DateTime.now(),
        style: widget.routeStyle,
        distanceKm: widget.distanceKm,
        curves: widget.curves,
        isRoundTrip: widget.isRoundTrip,
      ),
    );
    _xpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _xpAnimation = IntTween(begin: 0, end: widget.xpEarned).animate(
      CurvedAnimation(parent: _xpController, curve: Curves.easeOutCubic),
    );
    _xpController.forward();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _xpController.dispose();
    super.dispose();
  }

  /// Foto wählen + Ausschnitt/Zoom frei festlegen (was genau + in welchem
  /// Ausmaß gezeigt wird). Fließt in die teilbare Share-Card UND wird beim
  /// Speichern dauerhaft an der Fahrt persistiert (nicht nur im RAM).
  Future<void> _pickPhoto() async {
    if (_isPickingPhoto || _abgeschickt || _isSharing) return;
    setState(() => _isPickingPhoto = true);
    try {
      final bytes = await pickAndCropRidePhoto(context, lockedAspect: 4 / 3);
      if (bytes != null && mounted) {
        setState(() => _photoBytes = bytes);
      }
    } catch (e) {
      debugPrint('[CruiseCompletion] Foto wählen fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _isPickingPhoto = false);
    }
  }

  /// 2026-08-04: Solange das Sheet offen ist, liegt das Foto nur im Speicher.
  /// Hochgeladen wird erst im Hintergrund nach dem Speichern — es kann hier
  /// also keine verwaiste Datei mehr im Storage geben, die aufzuräumen wäre.
  void _removePhoto() {
    setState(() => _photoBytes = null);
  }

  /// 2026-08-04 (vucko): „Wenn man Speichern oder Verwerfen klickt, dauert es
  /// 15-20 Sekunden, bis wirklich reagiert wird, und dann können die User die
  /// App nicht richtig benutzen. Die UI soll direkt reagieren und das Backend
  /// soll sich seine Zeit nehmen."
  ///
  /// Genau das passiert hier: Wir geben die Eingaben nach draußen und schließen
  /// SOFORT. Kein await, kein „Speichert..."-Knopf mehr. Foto-Upload, die acht
  /// Supabase-Aufrufe und die XP-Synchronisierung laufen auf der Seite darunter
  /// weiter; die Level- und Badge-Feier erscheint dort, sobald sie fertig ist.
  ///
  /// [publish] führt nach dem Hintergrund-Speichern in den Post-Editor.
  void _handleSave({bool publish = false}) {
    if (_abgeschickt || _isSharing) return;
    _abgeschickt = true;
    final title = _titleController.text.trim();
    // Das Schliessen steht im finally: Wirft der Rueckruf, darf der Nutzer
    // trotzdem nicht in einem Sheet festsitzen, das sich nicht mehr schliessen
    // laesst. Genau dafuer gibt es den Test „schliesst auch wenn der Sync
    // fehlschlaegt".
    try {
      widget.onSave(
        _selectedRating > 0 ? _selectedRating : null,
        _selectedTags.toList(growable: false),
        title.isEmpty ? null : title,
        _photoBytes,
        publish,
      );
    } catch (error) {
      debugPrint('[CruiseCompletion] Speichern-Rueckruf warf: $error');
    } finally {
      Navigator.of(context).pop();
    }
  }

  /// „Wie waer's danach?" — zwei leise Wege in die Gruppen- und Community-Welt.
  Widget _buildFolgeVorschlaege() {
    final busy = _abgeschickt || _isSharing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Wie wär\'s danach?',
          style: TextStyle(
            color: Color(0xFFA8AFBC),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _FolgeChip(
                icon: Icons.group_add_outlined,
                label: 'Nächstes Mal zu zweit',
                onTap: busy ? null : _handleGruppeErstellen,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _FolgeChip(
                icon: Icons.forum_outlined,
                label: 'In die Community',
                onTap: busy ? null : () => _handleSave(publish: true),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Speichert wie gewohnt und uebergibt danach an die Seite, die zum
  /// Gruppe-Erstellen weiterleitet. Das Speichern laeuft im Hintergrund —
  /// deshalb darf gleich weitergeblaettert werden.
  void _handleGruppeErstellen() {
    final weiter = widget.onGruppeErstellen;
    _handleSave();
    weiter?.call();
  }

  void _handleDiscard() {
    if (_abgeschickt || _isSharing) return;
    _abgeschickt = true;
    try {
      widget.onDiscard();
    } catch (error) {
      debugPrint('[CruiseCompletion] Verwerfen-Rueckruf warf: $error');
    } finally {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleShare() async {
    if (_abgeschickt || _isSharing) return;
    final pixelRatio = MediaQuery.of(context).devicePixelRatio.clamp(2.0, 3.0);
    setState(() {
      _isSharing = true;
      _isExportMode = true;
    });

    try {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final boundary =
          _shareCardKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Share-Card nicht verfügbar');
      }
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      // 2026-06-15 (vucko M5 OOM): die ui.Image hält GPU/Native-Speicher — nach
      // dem Byte-Export sofort freigeben, sonst Speicher-Spitze beim Teilen.
      image.dispose();
      if (byteData == null) {
        throw Exception('PNG-Export fehlgeschlagen');
      }

      final pngBytes = byteData.buffer.asUint8List();
      final shareFile = XFile.fromData(
        pngBytes,
        mimeType: 'image/png',
        name: 'cruiseconnect-ride.png',
      );

      if (mounted) {
        setState(() => _isExportMode = false);
      }

      if (!mounted) return;
      final titleText = _titleController.text.trim();
      final shareText = titleText.isEmpty
          ? 'Meine Fahrt mit Cruise Connector'
          : '$titleText · ${widget.distanceKm.toStringAsFixed(1)} km mit Cruise Connector';
      await shareFiles(
        context,
        [shareFile],
        text: shareText,
        fileNameOverrides: const ['cruiseconnect-ride.png'],
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isExportMode = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Teilen fehlgeschlagen. Bitte erneut versuchen.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
          _isExportMode = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight =
            (constraints.maxHeight * 0.82 - bottomInset - 16)
                .clamp(420.0, 860.0)
                .toDouble();

        return Padding(
          padding: EdgeInsets.fromLTRB(
            10,
            42,
            10,
            _isExportMode ? 0 : bottomInset,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              RepaintBoundary(
                key: _shareCardKey,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  constraints: BoxConstraints(
                    maxWidth: 440,
                    maxHeight: _isExportMode
                        ? double.infinity
                        : availableHeight,
                  ),
                  padding: EdgeInsets.fromLTRB(
                    18,
                    14,
                    18,
                    _isExportMode ? 8 : 14,
                  ),
                  decoration: _buildCardDecoration(),
                  child: _isExportMode
                      ? _buildExportContent()
                      : _buildInteractiveContent(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExportContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPhotoBanner(),
        _buildSheetHeader(),
        const SizedBox(height: 14),
        _buildStatsGrid(),
        const SizedBox(height: 14),
        _RoutePreviewCard(
          coordinates: widget.routeCoordinates,
          segments: widget.routeSegments,
          drivenSegments: widget.drivenSegments,
          exportMode: true,
        ),
      ],
    );
  }

  Widget _buildInteractiveContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPhotoBanner(),
        _buildSheetHeader(),
        const SizedBox(height: 12),
        Flexible(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatsGrid(),
                if (_showStreakBonus) ...[
                  const SizedBox(height: 8),
                  _buildStreakBonusNote(),
                ],
                const SizedBox(height: 10),
                _RoutePreviewCard(
                  coordinates: widget.routeCoordinates,
                  segments: widget.routeSegments,
                  drivenSegments: widget.drivenSegments,
                  exportMode: false,
                ),
                if (widget.drivenSegments != null &&
                    widget.drivenSegments!.any((s) => s.length >= 2)) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _LegendDot(
                        color: Color(0xAAFFFFFF),
                        label: 'Geplant',
                      ),
                      const SizedBox(width: 14),
                      _LegendDot(
                        color: AppAccentColors.accent,
                        label: 'Wirklich gefahren',
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                _buildPhotoControl(),
                const SizedBox(height: 10),
                _buildRatingPanel(),
                if (widget.folgeVorschlaege) ...[
                  const SizedBox(height: 12),
                  _buildFolgeVorschlaege(),
                ],
                if (widget.belowMinimum) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Unter 20% Fahranteil: Route kann gespeichert werden, XP wird fairerweise nicht gutgeschrieben.',
                    style: TextStyle(
                      color: Color(0xFFA8AFBC),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildActionRow(),
      ],
    );
  }

  Widget _buildSheetHeader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'CRUISE CONNECTOR',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFA8AFBC),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 6),
        // 2026-05-31 (vucko): Automatisch generierter, passender Titel
        // ("Sportlicher Donnerstagabend") — editierbar wie bei Strava.
        _buildTitleField(),
        const SizedBox(height: 10),
        const _CruiseRedDivider(),
      ],
    );
  }

  Widget _buildTitleField() {
    final titleText = _titleController.text.trim();
    // Export/Teilen-Karte: reiner Text (kein Cursor/Border im PNG).
    if (_isExportMode) {
      return Text(
        titleText.isEmpty ? 'Meine Fahrt' : titleText,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 21,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      );
    }
    // Interaktiv: editierbar. Der Stift signalisiert „antippen zum Ändern".
    return TextField(
      controller: _titleController,
      textAlign: TextAlign.center,
      textCapitalization: TextCapitalization.sentences,
      maxLength: 48,
      maxLines: 1,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 21,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
      cursorColor: AppAccentColors.accent,
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 2),
        hintText: 'Titel der Fahrt',
        hintStyle: const TextStyle(color: Color(0xFF8A93A6)),
        suffixIcon: Icon(
          Icons.edit_outlined,
          size: 16,
          color: AppAccentColors.accent.withValues(alpha: 0.8),
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 26,
          minHeight: 26,
        ),
      ),
    );
  }

  /// Eigenes Foto als Banner oben in der (teilbaren) Karte.
  Widget _buildPhotoBanner() {
    final bytes = _photoBytes;
    if (bytes == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Image.memory(bytes, fit: BoxFit.cover),
        ),
      ),
    );
  }

  /// „Foto hinzufügen/ändern" + optional „Entfernen". Nur interaktiv.
  Widget _buildPhotoControl() {
    final hasPhoto = _photoBytes != null;
    final busy = _isPickingPhoto || _abgeschickt || _isSharing;
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: hasPhoto
                ? Icons.swap_horiz_rounded
                : Icons.add_a_photo_outlined,
            label: _isPickingPhoto
                ? 'Öffne…'
                : (hasPhoto ? 'Foto ändern' : 'Foto hinzufügen'),
            onTap: _pickPhoto,
            disabled: busy,
          ),
        ),
        if (hasPhoto) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _ActionButton(
              icon: Icons.delete_outline_rounded,
              label: 'Entfernen',
              onTap: _removePhoto,
              disabled: _abgeschickt || _isSharing,
            ),
          ),
        ],
      ],
    );
  }

  Decoration? _buildCardDecoration() {
    if (_isExportMode) return null;
    return const BoxDecoration(
      color: Color(0x33FFFFFF),
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(24),
        topRight: Radius.circular(24),
      ),
      border: Border.fromBorderSide(
        BorderSide(color: Colors.white24, width: 1),
      ),
    );
  }

  Widget _buildStatsGrid() {
    final xpLabel = widget.belowMinimum
        ? 'XP nicht aktiv'
        : widget.xpMultiplier > 1
        ? 'XP x${widget.xpMultiplier.toStringAsFixed(2)}'
        : 'XP';
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                value: '${widget.distanceKm.toStringAsFixed(1)} km',
                label: 'Distanz',
                exportMode: _isExportMode,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                value: widget.durationText,
                label: 'Dauer',
                exportMode: _isExportMode,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                value: '${widget.curves}',
                label: 'Kurven',
                exportMode: _isExportMode,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                label: xpLabel,
                exportMode: _isExportMode,
                animatedValue: _xpAnimation,
              ),
            ),
          ],
        ),
        // 2026-06-23 (vucko Post-Route Top-Speed): dritte Reihe — Top-Speed +
        // Ø-Tempo. Nur zeigen, wenn echte Werte vorliegen (Single + Gruppe).
        if (widget.topSpeedKmh > 0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  value: '${widget.topSpeedKmh.round()} km/h',
                  label: 'Top-Speed',
                  exportMode: _isExportMode,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  value: widget.avgSpeedKmh > 0
                      ? '${widget.avgSpeedKmh.round()} km/h'
                      : '—',
                  label: 'Ø Tempo',
                  exportMode: _isExportMode,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  bool get _showStreakBonus =>
      !widget.belowMinimum && widget.xpMultiplier > 1 && widget.baseXp != null;

  Widget _buildStreakBonusNote() {
    // 2026-06-15 (vucko): den ECHT verdienten Streak-Bonus zeigen (klarer +
    // belohnender als die nackte Rechnung), im selben Accent-Pill — kein
    // Layout-Eingriff. Multiplikator deutsch mit Komma.
    final base = widget.baseXp ?? 0;
    final bonusXp = (base * (widget.xpMultiplier - 1)).round();
    final mulText = widget.xpMultiplier.toStringAsFixed(1).replaceAll('.', ',');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppAccentColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppAccentColors.accent.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              '${widget.streakDays} ${widget.streakDays == 1 ? 'Tag' : 'Tage'} Streak · +$bonusXp XP Bonus (×$mulText)',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    // 2026-08-03 (vucko Route-Aufzeichnen): Eigene Zeile statt vierter Button in
    // der Reihe — zu viert wären die Labels nicht mehr lesbar. Nur sichtbar,
    // wenn canPublish gesetzt ist (= aufgezeichnete Strecke).
    if (widget.canPublish) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: _ActionButton(
              icon: Icons.public_rounded,
              label: 'Speichern & veröffentlichen',
              onTap: () => _handleSave(publish: true),
              filled: true,
              disabled: _abgeschickt || _isSharing,
            ),
          ),
          const SizedBox(height: 10),
          _buildDefaultActionRow(),
        ],
      );
    }
    return _buildDefaultActionRow();
  }

  Widget _buildDefaultActionRow() {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.check_rounded,
            label: 'Speichern',
            onTap: _handleSave,
            filled: !widget.canPublish,
            disabled: _abgeschickt || _isSharing,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.north_rounded,
            label: _isSharing ? 'Teilt...' : 'Teilen',
            onTap: _handleShare,
            disabled: _abgeschickt || _isSharing,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.close_rounded,
            label: 'Verwerfen',
            onTap: _handleDiscard,
            disabled: _abgeschickt || _isSharing,
          ),
        ),
      ],
    );
  }

  Widget _buildRatingPanel() {
    const detailTags = <String>[
      'schöne Kurven',
      'guter Flow',
      'passende Länge',
      'zu künstlich',
      'zu kurz/lang',
      'Autobahn trotz AUS',
      'wiederholt',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: const Color(0xFF111720).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppAccentColors.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: AppAccentColors.accent.withValues(alpha: 0.26),
                  ),
                ),
                child: Icon(
                  Icons.route_rounded,
                  color: AppAccentColors.accent,
                  size: 15,
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wie war diese Route?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Kurz bewerten. Details sind optional.',
                      style: TextStyle(
                        color: Color(0xFFA8AFBC),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final chipWidth = (constraints.maxWidth - 12) / 3;
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  SizedBox(
                    width: chipWidth,
                    child: _QualityChoiceButton(
                      label: 'Top',
                      selected: _selectedRating >= 5,
                      onTap: () => setState(() => _selectedRating = 5),
                    ),
                  ),
                  SizedBox(
                    width: chipWidth,
                    child: _QualityChoiceButton(
                      label: 'Okay',
                      selected: _selectedRating >= 3 && _selectedRating < 5,
                      onTap: () => setState(() => _selectedRating = 3),
                    ),
                  ),
                  SizedBox(
                    width: chipWidth,
                    child: _QualityChoiceButton(
                      label: 'Schlecht',
                      selected: _selectedRating > 0 && _selectedRating < 3,
                      onTap: () => setState(() => _selectedRating = 1),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () =>
                  setState(() => _showRatingDetails = !_showRatingDetails),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  _showRatingDetails
                      ? 'Details ausblenden'
                      : 'Details optional',
                  style: TextStyle(
                    color: AppAccentColors.accent.withValues(alpha: 0.92),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final tag in detailTags)
                    _RatingTagChip(
                      label: tag,
                      selected: _selectedTags.contains(tag),
                      positive:
                          !tag.startsWith('zu ') &&
                          tag != 'Autobahn trotz AUS' &&
                          tag != 'wiederholt',
                      onTap: () {
                        setState(() {
                          if (!_selectedTags.add(tag)) {
                            _selectedTags.remove(tag);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
            crossFadeState: _showRatingDetails
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}

class _CruiseRedDivider extends StatelessWidget {
  const _CruiseRedDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 2,
      decoration: BoxDecoration(
        color: AppAccentColors.accent,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.exportMode,
    this.value,
    this.animatedValue,
  });

  final String? value;
  final String label;
  final bool exportMode;
  final Animation<int>? animatedValue;

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(
      color: Colors.white,
      fontSize: exportMode ? 24 : 19,
      fontWeight: FontWeight.w800,
      height: 1.0,
      letterSpacing: -0.2,
    );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: exportMode ? 14 : 12,
        vertical: exportMode ? 14 : 10,
      ),
      decoration: BoxDecoration(
        color: exportMode
            ? Colors.transparent
            : Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(exportMode ? 18 : 15),
        border: exportMode
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          animatedValue != null
              ? AnimatedBuilder(
                  animation: animatedValue!,
                  builder: (context, child) {
                    return FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('${animatedValue!.value}', style: valueStyle),
                    );
                  },
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value ?? '--', style: valueStyle),
                ),
          SizedBox(height: exportMode ? 6 : 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFFA8AFBC),
              fontSize: exportMode ? 11 : 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.disabled = false,
  });

  final IconData icon;
  final String label;

  /// 2026-08-04: War `Future<void> Function()`. Seit Speichern und Verwerfen
  /// sofort zurückkehren, sind es einfache Rückrufe; „Teilen" ist weiterhin
  /// asynchron und passt trotzdem (Dart erlaubt jeden Rückgabetyp für void).
  final VoidCallback onTap;
  final bool filled;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : () => onTap(),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: disabled ? 0.55 : 1,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: filled
                ? AppAccentColors.accent
                : Colors.black.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: filled ? Colors.transparent : Colors.white24,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 17),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatingTagChip extends StatelessWidget {
  const _RatingTagChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.positive,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final accent = positive ? AppAccentColors.accent : const Color(0xFFFF6B6B);
    return Semantics(
      button: true,
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.20)
                : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? accent : Colors.white.withValues(alpha: 0.11),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFFA8AFBC),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1.05,
            ),
          ),
        ),
      ),
    );
  }
}

class _QualityChoiceButton extends StatelessWidget {
  const _QualityChoiceButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 34,
          decoration: BoxDecoration(
            color: selected
                ? AppAccentColors.accent.withValues(alpha: 0.24)
                : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AppAccentColors.accent
                  : Colors.white.withValues(alpha: 0.11),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFA8AFBC),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoutePreviewCard extends StatelessWidget {
  const _RoutePreviewCard({
    required this.coordinates,
    required this.exportMode,
    this.segments,
    this.drivenSegments,
  });

  final List<List<double>> coordinates;
  final List<List<List<double>>>? segments;
  final List<List<List<double>>>? drivenSegments;
  final bool exportMode;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(exportMode ? 22 : 18),
      child: Container(
        height: exportMode ? 184 : 112,
        decoration: BoxDecoration(
          color: exportMode ? Colors.transparent : const Color(0xFF131821),
          borderRadius: BorderRadius.circular(exportMode ? 22 : 18),
          border: exportMode
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _RoutePreviewPainter(
                  coordinates: coordinates,
                  segments: segments,
                  drivenSegments: drivenSegments,
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Cruise Connector Route',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutePreviewPainter extends CustomPainter {
  _RoutePreviewPainter({
    required this.coordinates,
    this.segments,
    this.drivenSegments,
  });

  final List<List<double>> coordinates;
  final List<List<List<double>>>? segments;

  /// 2026-05-24 (vucko Task #41): Echter GPS-Track (überlagert geplant).
  final List<List<List<double>>>? drivenSegments;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;

    for (var i = 1; i <= 3; i++) {
      final x = size.width * i / 4;
      final y = size.height * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final drawableSegments = _effectiveSegments();
    if (drawableSegments.isEmpty) return;
    final validDrivenSegments =
        _validSegments(drivenSegments) ?? const <List<List<double>>>[];

    final allPoints = drawableSegments.expand((segment) => segment).toList();
    double minLng = allPoints.first[0];
    double maxLng = allPoints.first[0];
    double minLat = allPoints.first[1];
    double maxLat = allPoints.first[1];
    for (final point in allPoints) {
      minLng = point[0] < minLng ? point[0] : minLng;
      maxLng = point[0] > maxLng ? point[0] : maxLng;
      minLat = point[1] < minLat ? point[1] : minLat;
      maxLat = point[1] > maxLat ? point[1] : maxLat;
    }

    final width = (maxLng - minLng).abs().clamp(0.00001, double.infinity);
    final height = (maxLat - minLat).abs().clamp(0.00001, double.infinity);
    const padding = 18.0;
    Offset project(List<double> point) {
      return Offset(
        padding + ((point[0] - minLng) / width) * (size.width - padding * 2),
        size.height -
            padding -
            ((point[1] - minLat) / height) * (size.height - padding * 2),
      );
    }

    // 2026-05-24 (vucko Task #41): Zwei-Layer-Rendering wenn DrivenTrack
    // verfügbar. Geplante Route in dezentem Grau, echter Track in accent.
    final hasDrivenTrack = validDrivenSegments.isNotEmpty;

    final plannedColor = hasDrivenTrack
        ? const Color(0x66FFFFFF)
        : AppAccentColors.accent;
    final plannedGlowAlpha = hasDrivenTrack ? 0.12 : 0.40;

    final glowPaint = Paint()
      ..color = plannedColor.withValues(alpha: plannedGlowAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    final routePaint = Paint()
      ..color = hasDrivenTrack
          ? const Color(0xAAFFFFFF)
          : Color.lerp(AppAccentColors.accent, Colors.white, 0.10)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = hasDrivenTrack ? 3 : 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final segment in drawableSegments) {
      final routePath = Path();
      for (var i = 0; i < segment.length; i++) {
        final point = project(segment[i]);
        if (i == 0) {
          routePath.moveTo(point.dx, point.dy);
        } else {
          routePath.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(routePath, glowPaint);
      canvas.drawPath(routePath, routePaint);
    }

    // Echter gefahrener Track als accent-Overlay
    if (hasDrivenTrack) {
      final drivenGlow = Paint()
        ..color = AppAccentColors.accent.withValues(alpha: 0.50)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11);
      final drivenLine = Paint()
        ..color = AppAccentColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final segment in validDrivenSegments) {
        final p = Path();
        for (var i = 0; i < segment.length; i++) {
          final pt = project(segment[i]);
          if (i == 0) {
            p.moveTo(pt.dx, pt.dy);
          } else {
            p.lineTo(pt.dx, pt.dy);
          }
        }
        canvas.drawPath(p, drivenGlow);
        canvas.drawPath(p, drivenLine);
      }
    }

    final start = project(drawableSegments.first.first);
    final end = project(drawableSegments.last.last);
    canvas.drawCircle(start, 5, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(end, 5, Paint()..color = AppAccentColors.accent);
  }

  @override
  bool shouldRepaint(covariant _RoutePreviewPainter oldDelegate) {
    return oldDelegate.coordinates != coordinates ||
        oldDelegate.segments != segments ||
        oldDelegate.drivenSegments != drivenSegments;
  }

  List<List<List<double>>> _effectiveSegments() {
    final provided = _validSegments(segments);
    if (provided != null && provided.isNotEmpty) return provided;
    final route = coordinates
        .where(_isValidPoint)
        .map((point) => [point[0], point[1]])
        .toList(growable: false);
    if (route.length >= 2) return [route];
    final driven = _validSegments(drivenSegments);
    if (driven != null && driven.isNotEmpty) return driven;
    return const [];
  }

  List<List<List<double>>>? _validSegments(List<List<List<double>>>? raw) {
    return raw
        ?.map(
          (segment) => segment
              .where(_isValidPoint)
              .map((point) => [point[0], point[1]])
              .toList(growable: false),
        )
        .where((segment) => segment.length >= 2)
        .toList(growable: false);
  }

  bool _isValidPoint(List<double> point) {
    return point.length >= 2 && point[0].isFinite && point[1].isFinite;
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xCCFFFFFF),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}


/// Leiser Vorschlags-Knopf: umrandet statt gefuellt, damit er neben den echten
/// Aktionen („Speichern", „Verwerfen") nicht um Aufmerksamkeit kaempft.
class _FolgeChip extends StatelessWidget {
  const _FolgeChip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final aus = onTap == null;
    return SizedBox(
      height: 36,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          side: BorderSide(
            color: Colors.white.withValues(alpha: aus ? 0.06 : 0.12),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          foregroundColor: Colors.white,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: Colors.white.withValues(alpha: aus ? 0.3 : 0.7),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: aus ? 0.3 : 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
