import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

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
                child: Container(
                  color: Colors.black.withValues(alpha: 0.08),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: child,
              ),
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
  const CruiseCompletionActionResult({
    this.success = true,
    this.newBadgeEmojis = const [],
    this.levelUp = false,
    this.newLevel,
  });

  final bool success;
  final List<String> newBadgeEmojis;
  final bool levelUp;
  final int? newLevel;

  bool get hasCelebration => newBadgeEmojis.isNotEmpty || levelUp;
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
    this.isEarlyStop = false,
    this.belowMinimum = false,
  });

  final double distanceKm;
  final String durationText;
  final int curves;
  final int xpEarned;
  final List<List<double>> routeCoordinates;
  final Future<CruiseCompletionActionResult> Function() onSave;
  final Future<void> Function() onDiscard;
  final bool isEarlyStop;
  final bool belowMinimum;

  @override
  State<CruiseCompletionDialog> createState() => _CruiseCompletionDialogState();
}

class _CruiseCompletionDialogState extends State<CruiseCompletionDialog>
    with TickerProviderStateMixin {
  final GlobalKey _shareCardKey = GlobalKey();
  late final AnimationController _xpController;
  late final Animation<int> _xpAnimation;
  late final AnimationController _celebrationController;
  bool _isExportMode = false;
  bool _isSaving = false;
  bool _isSharing = false;
  CruiseCompletionActionResult? _celebration;

  @override
  void initState() {
    super.initState();
    _xpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _xpAnimation = IntTween(
      begin: 0,
      end: widget.xpEarned,
    ).animate(CurvedAnimation(parent: _xpController, curve: Curves.easeOutCubic));
    _xpController.forward();

    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _xpController.dispose();
    _celebrationController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_isSaving || _isSharing) return;
    setState(() => _isSaving = true);
    final result = await widget.onSave();
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (!result.success) return;

    if (result.hasCelebration) {
      setState(() => _celebration = result);
      await _celebrationController.forward(from: 0);
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _handleDiscard() async {
    if (_isSaving || _isSharing) return;
    await widget.onDiscard();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _handleShare() async {
    if (_isSaving || _isSharing) return;
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

      await Share.shareXFiles(
        [shareFile],
        text: 'Meine Fahrt mit CruiseConnect',
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

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 48, 12, _isExportMode ? 0 : bottomInset),
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            key: _shareCardKey,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20, 16, 20, _isExportMode ? 8 : 18),
              decoration: _buildCardDecoration(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'CruiseConnect',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _CruiseRedDivider(),
                  const SizedBox(height: 16),
                  _buildStatsGrid(),
                  const SizedBox(height: 18),
                  _RoutePreviewCard(
                    coordinates: widget.routeCoordinates,
                    exportMode: _isExportMode,
                  ),
                  const SizedBox(height: 18),
                  const _CruiseRedDivider(),
                  if (!_isExportMode) ...[
                    const SizedBox(height: 16),
                    _buildActionRow(),
                    if (widget.belowMinimum) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Unter 10% Fahranteil: gespeichert ohne XP-Gutschrift.',
                        style: TextStyle(
                          color: Color(0xFFA8AFBC),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          if (_celebration != null) _buildCelebrationOverlay(),
        ],
      ),
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
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                value: widget.durationText,
                label: 'Dauer',
                exportMode: _isExportMode,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                value: '${widget.curves}',
                label: 'Kurven',
                exportMode: _isExportMode,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: widget.belowMinimum ? 'XP gesperrt' : 'XP earned',
                exportMode: _isExportMode,
                animatedValue: _xpAnimation,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.check_rounded,
            label: _isSaving ? 'Speichert...' : 'Speichern',
            onTap: _handleSave,
            filled: true,
            disabled: _isSaving || _isSharing,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.north_rounded,
            label: _isSharing ? 'Teilt...' : 'Teilen',
            onTap: _handleShare,
            disabled: _isSaving || _isSharing,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.close_rounded,
            label: 'Verwerfen',
            onTap: _handleDiscard,
            disabled: _isSaving || _isSharing,
          ),
        ),
      ],
    );
  }

  Widget _buildCelebrationOverlay() {
    final emojis = _celebration!.newBadgeEmojis.join(' ');
    final label = _celebration!.levelUp
        ? 'Level ${_celebration!.newLevel} erreicht'
        : 'Neues Badge freigeschaltet';

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _celebrationController,
        builder: (context, child) {
          final t = Curves.easeOutBack.transform(_celebrationController.value);
          final fade = (1 - (_celebrationController.value - 0.7).clamp(0.0, 0.3) / 0.3)
              .clamp(0.0, 1.0);
          const bursts = <Offset>[
            Offset(-84, -26),
            Offset(-54, -74),
            Offset(0, -92),
            Offset(54, -74),
            Offset(84, -26),
            Offset(-68, 40),
            Offset(68, 40),
          ];

          return Opacity(
            opacity: fade,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 180,
                    height: 180,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0x44FF3B30), Colors.transparent],
                      ),
                    ),
                  ),
                  for (final burst in bursts)
                    Transform.translate(
                      offset: Offset(burst.dx * t, burst.dy * t),
                      child: Transform.scale(
                        scale: 0.7 + (0.6 * t),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFFFFD76A),
                          size: 18,
                        ),
                      ),
                    ),
                  Transform.scale(
                    scale: 0.82 + (0.18 * t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (emojis.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              emojis,
                              style: const TextStyle(fontSize: 26),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
        color: const Color(0xFFFF3B30),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: exportMode ? Colors.transparent : Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
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
                    return Text(
                      '${animatedValue!.value}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    );
                  },
                )
              : Text(
                  value ?? '--',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFA8AFBC),
              fontSize: 11,
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
  final Future<void> Function() onTap;
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
          height: 48,
          decoration: BoxDecoration(
            color: filled
                ? const Color(0xFFFF3B30)
                : Colors.black.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: filled ? Colors.transparent : Colors.white24,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
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
  });

  final List<List<double>> coordinates;
  final bool exportMode;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 184,
        decoration: BoxDecoration(
          color: const Color(0xFF131821),
          borderRadius: BorderRadius.circular(22),
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
                  'Read only',
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
  const _RoutePreviewPainter({required this.coordinates});

  final List<List<double>> coordinates;

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

    if (coordinates.length < 2) return;

    double minLng = coordinates.first[0];
    double maxLng = coordinates.first[0];
    double minLat = coordinates.first[1];
    double maxLat = coordinates.first[1];
    for (final point in coordinates) {
      minLng = point[0] < minLng ? point[0] : minLng;
      maxLng = point[0] > maxLng ? point[0] : maxLng;
      minLat = point[1] < minLat ? point[1] : minLat;
      maxLat = point[1] > maxLat ? point[1] : maxLat;
    }

    final width = (maxLng - minLng).abs().clamp(0.00001, double.infinity);
    final height = (maxLat - minLat).abs().clamp(0.00001, double.infinity);
    const padding = 18.0;
    final routePath = Path();

    for (var i = 0; i < coordinates.length; i++) {
      final point = coordinates[i];
      final dx = padding + ((point[0] - minLng) / width) * (size.width - padding * 2);
      final dy =
          size.height -
          padding -
          ((point[1] - minLat) / height) * (size.height - padding * 2);
      if (i == 0) {
        routePath.moveTo(dx, dy);
      } else {
        routePath.lineTo(dx, dy);
      }
    }

    final glowPaint = Paint()
      ..color = const Color(0x66FF6A5B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    final routePaint = Paint()
      ..color = const Color(0xFFFF5A5A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(routePath, glowPaint);
    canvas.drawPath(routePath, routePaint);

    final metrics = routePath.computeMetrics().toList();
    if (metrics.isNotEmpty) {
      final start = metrics.first.getTangentForOffset(0)?.position;
      final end = metrics.last.getTangentForOffset(metrics.last.length)?.position;
      if (start != null) {
        canvas.drawCircle(
          start,
          5,
          Paint()..color = const Color(0xFFFFFFFF),
        );
      }
      if (end != null) {
        canvas.drawCircle(
          end,
          5,
          Paint()..color = const Color(0xFFFF3B30),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePreviewPainter oldDelegate) {
    return oldDelegate.coordinates != coordinates;
  }
}
