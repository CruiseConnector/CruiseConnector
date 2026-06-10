import 'package:flutter/material.dart';

import 'package:cruise_connect/presentation/widgets/car_card.dart';

class VehicleGarageCarousel extends StatefulWidget {
  const VehicleGarageCarousel({
    super.key,
    required this.vehicles,
    this.onAddVehicle,
    this.onVehicleTap,
    this.onVehicleChanged,
    this.selectedIndex = 0,
    this.vehicleBuilder,
    this.viewportFraction = 0.96,
    this.height,
  });

  final List<Map<String, dynamic>> vehicles;
  final VoidCallback? onAddVehicle;
  final ValueChanged<int>? onVehicleTap;
  final ValueChanged<int>? onVehicleChanged;
  final int selectedIndex;
  final Widget Function(BuildContext context, int index)? vehicleBuilder;
  final double viewportFraction;
  final double? height;

  @override
  State<VehicleGarageCarousel> createState() => _VehicleGarageCarouselState();
}

class _VehicleGarageCarouselState extends State<VehicleGarageCarousel> {
  late final PageController _controller;
  int _page = 0;

  int get _pageCount =>
      widget.vehicles.length + (widget.onAddVehicle == null ? 0 : 1);

  @override
  void initState() {
    super.initState();
    _page = _safeSelectedPage;
    _controller = PageController(
      viewportFraction: widget.viewportFraction,
      initialPage: _page,
    );
  }

  int get _safeSelectedPage {
    if (_pageCount <= 0) return 0;
    return widget.selectedIndex.clamp(0, _pageCount - 1).toInt();
  }

  @override
  void didUpdateWidget(covariant VehicleGarageCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextPage = _safeSelectedPage;
    if (nextPage == _page &&
        oldWidget.vehicles.length == widget.vehicles.length) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final safePage = _safeSelectedPage;
      if (_page != safePage) setState(() => _page = safePage);
      if (_controller.hasClients &&
          (_controller.page?.round() ?? _controller.initialPage) != safePage) {
        _controller.animateToPage(
          safePage,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePageChanged(int value) {
    if (_page != value) setState(() => _page = value);
    if (value < widget.vehicles.length) {
      widget.onVehicleChanged?.call(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pageCount == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth * 0.92 - 10).clamp(
              260.0,
              constraints.maxWidth,
            );
            final preferredHeight =
                widget.height ??
                widget.vehicles.fold<double>(CarCard.baseHeight, (
                  value,
                  vehicle,
                ) {
                  final preferred = CarCard.preferredHeightFor(
                    vehicle,
                    width: cardWidth,
                  );
                  return value > preferred ? value : preferred;
                });
            return SizedBox(
              height: preferredHeight,
              child: PageView.builder(
                controller: _controller,
                itemCount: _pageCount,
                onPageChanged: _handlePageChanged,
                itemBuilder: (context, index) {
                  final isAddCard = index >= widget.vehicles.length;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: isAddCard
                        ? _AddVehicleCard(onTap: widget.onAddVehicle!)
                        : widget.vehicleBuilder?.call(context, index) ??
                              CarCard(
                                profile: widget.vehicles[index],
                                onTap: widget.onVehicleTap == null
                                    ? null
                                    : () => widget.onVehicleTap!(index),
                              ),
                  );
                },
              ),
            );
          },
        ),
        if (_pageCount > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _pageCount; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? CarCard.accent
                        : Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AddVehicleCard extends StatelessWidget {
  const _AddVehicleCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: constraints.maxHeight,
            width: double.infinity,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1F26),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: CarCard.accent.withValues(alpha: 0.34),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.24),
                      blurRadius: 22,
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
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: CarCard.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: Icon(
                            Icons.add_rounded,
                            color: CarCard.accent,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Garage erweitern',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Tippe hier, um direkt eine neue Fahrzeugkarte anzulegen.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    const Row(
                      children: [
                        _GarageAddChip(
                          icon: Icons.directions_car_filled_rounded,
                          label: 'Auto',
                        ),
                        SizedBox(width: 8),
                        _GarageAddChip(
                          icon: Icons.two_wheeler_rounded,
                          label: 'Motorrad',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GarageAddChip extends StatelessWidget {
  const _GarageAddChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: CarCard.accent, size: 17),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
