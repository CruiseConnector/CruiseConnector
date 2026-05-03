import 'package:flutter/material.dart';

import 'package:cruise_connect/presentation/widgets/car_card.dart';

class VehicleGarageCarousel extends StatefulWidget {
  const VehicleGarageCarousel({
    super.key,
    required this.vehicles,
    this.onAddVehicle,
    this.onVehicleTap,
    this.height,
  });

  final List<Map<String, dynamic>> vehicles;
  final VoidCallback? onAddVehicle;
  final ValueChanged<int>? onVehicleTap;
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
    _controller = PageController(viewportFraction: 0.92);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePageChanged(int value) {
    if (_page == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _page == value) return;
      setState(() => _page = value);
    });
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
            final height =
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
              height: height,
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
                        : CarCard(
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1F26),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: CarCard.accent.withValues(alpha: 0.34),
            width: 1.2,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: CarCard.accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: CarCard.accent,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Weiteres Auto/Motorrad hinzufügen',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Lege deine Garage an und swipe zwischen deinen Fahrzeugen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
