import 'package:flutter/material.dart';

import 'package:cruise_connect/data/services/favorite_routes_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/widgets/profile/favorite_route_preview.dart';

/// Die angepinnten Top-3-Routen eines Profils.
///
/// 2026-08-19 (Top-3-Lieblingsrouten): Dasselbe Widget im eigenen und im
/// fremden Profil — [isOwner] schaltet nur das Bearbeiten frei. Zwei getrennte
/// Darstellungen waeren zwei Orte, an denen dasselbe Layout auseinanderlaeuft.
class FavoriteRoutesShowcase extends StatelessWidget {
  const FavoriteRoutesShowcase({
    super.key,
    required this.routes,
    required this.accent,
    required this.isOwner,
    required this.onOpenRoute,
    this.onEdit,
    this.displayName,
  });

  final List<SavedRoute> routes;
  final Color accent;

  /// Eigenes Profil? Dann Stift-Button und Hinweis-Kachel, wenn noch nichts
  /// angepinnt ist.
  final bool isOwner;
  final ValueChanged<SavedRoute> onOpenRoute;
  final VoidCallback? onEdit;

  /// Name des Profilinhabers — nur fuer die Ueberschrift auf fremden Profilen.
  final String? displayName;

  @override
  Widget build(BuildContext context) {
    // Fremdes Profil ohne Highlights: gar keine Ueberschrift. Eine leere
    // Sektion auf einem fremden Profil ist Rauschen.
    if (routes.isEmpty && !isOwner) return const SizedBox.shrink();

    final visible = routes.take(FavoriteRoutesService.maxFavorites).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          _buildEmptyPrompt()
        else ...[
          SizedBox(
            height: 168,
            child: _RouteHighlightCard(
              route: visible.first,
              rank: 1,
              accent: accent,
              onTap: () => onOpenRoute(visible.first),
            ),
          ),
          if (visible.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 118,
              child: Row(
                children: [
                  for (var i = 1; i < visible.length; i++) ...[
                    if (i > 1) const SizedBox(width: 10),
                    Expanded(
                      child: _RouteHighlightCard(
                        route: visible[i],
                        rank: i + 1,
                        accent: accent,
                        compact: true,
                        onTap: () => onOpenRoute(visible[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildHeader() {
    final name = displayName?.trim();
    final title = isOwner || name == null || name.isEmpty
        ? 'Lieblingsrouten'
        : 'Lieblingsrouten von $name';

    return Row(
      children: [
        Icon(Icons.favorite_rounded, color: accent, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (isOwner && onEdit != null)
          TextButton.icon(
            onPressed: onEdit,
            style: TextButton.styleFrom(
              foregroundColor: accent,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.edit_rounded, size: 15),
            label: Text(
              routes.isEmpty ? 'Auswählen' : 'Ändern',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyPrompt() {
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF141821),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: 0.28), width: 1.2),
        ),
        child: Row(
          children: [
            Icon(Icons.push_pin_rounded, color: accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Zeig deine drei besten Strecken',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Angepinnte Routen stehen ganz oben in deinem Profil.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}

/// Eine einzelne Highlight-Kachel: Vorschau, Platznummer, Titel, Eckdaten.
class _RouteHighlightCard extends StatelessWidget {
  const _RouteHighlightCard({
    required this.route,
    required this.rank,
    required this.accent,
    required this.onTap,
    this.compact = false,
  });

  final SavedRoute route;
  final int rank;
  final Color accent;
  final VoidCallback onTap;

  /// Plaetze 2 und 3 stehen nebeneinander und haben halb so viel Breite —
  /// dort fallen Untertitel und Bewertung weg, statt zu klemmen.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final title = _title();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FavoriteRoutePreview(route: route, accent: accent),
              Positioned(top: 8, left: 8, child: _buildRankBadge()),
              Positioned(
                left: 10,
                right: 10,
                bottom: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 12.5 : 15,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 6),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildMetaRow(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _title() {
    final name = route.name?.trim();
    if (name != null && name.isNotEmpty) return name;
    return '${route.styleEmoji} ${route.displayStyleLabel}';
  }

  Widget _buildRankBadge() {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 8),
        ],
      ),
      child: Text(
        '$rank',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildMetaRow() {
    final rating = route.ratingShareLabel;
    return Row(
      children: [
        _chip(Icons.straighten_rounded, route.formattedDistance),
        const SizedBox(width: 6),
        _chip(Icons.schedule_rounded, route.durationLabelOrEstimate),
        if (!compact && rating != null) ...[
          const SizedBox(width: 6),
          _chip(Icons.star_rounded, rating),
        ],
      ],
    );
  }

  Widget _chip(IconData icon, String label) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: Colors.white.withValues(alpha: 0.8)),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
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
