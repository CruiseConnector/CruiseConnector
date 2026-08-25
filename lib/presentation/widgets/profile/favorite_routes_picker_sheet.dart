import 'package:flutter/material.dart';

import 'package:cruise_connect/data/services/favorite_routes_service.dart';
import 'package:cruise_connect/data/services/saved_routes_service.dart';
import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/presentation/widgets/profile/favorite_route_preview.dart';

/// Auswahl der bis zu drei Lieblingsrouten fuers eigene Profil.
///
/// Oeffnen ueber [show]; liefert die neue Auswahl zurueck oder `null`, wenn
/// abgebrochen wurde. Gespeichert wird erst beim Bestaetigen — Tippen in der
/// Liste darf noch nichts an der DB aendern, sonst kann man das versehentliche
/// Abwaehlen der Lieblingsroute nicht mehr zuruecknehmen.
class FavoriteRoutesPickerSheet extends StatefulWidget {
  const FavoriteRoutesPickerSheet({
    super.key,
    required this.accent,
    required this.initialSelection,
  });

  final Color accent;

  /// Aktuell angepinnte Routen in Anzeige-Reihenfolge.
  final List<SavedRoute> initialSelection;

  /// Liefert die gespeicherte Auswahl oder `null` bei Abbruch/Fehler.
  static Future<List<SavedRoute>?> show(
    BuildContext context, {
    required Color accent,
    required List<SavedRoute> initialSelection,
  }) {
    return showModalBottomSheet<List<SavedRoute>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => FavoriteRoutesPickerSheet(
        accent: accent,
        initialSelection: initialSelection,
      ),
    );
  }

  @override
  State<FavoriteRoutesPickerSheet> createState() =>
      _FavoriteRoutesPickerSheetState();
}

class _FavoriteRoutesPickerSheetState extends State<FavoriteRoutesPickerSheet> {
  /// Alle Routen, aus denen gewaehlt werden kann (eigene + gemerkte).
  List<SavedRoute> _library = const [];

  /// Route-IDs in der GEWAEHLTEN Reihenfolge — die Reihenfolge ist das
  /// Ergebnis (Platz 1..3), deshalb eine Liste und kein Set.
  late List<String> _selected;

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection
        .map((route) => route.id)
        .take(FavoriteRoutesService.maxFavorites)
        .toList();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    final library = await SavedRoutesService.getSavedRouteLibrary();
    if (!mounted) return;

    // Bereits angepinnte Routen, die nicht (mehr) in der Bibliothek stehen,
    // vorne anhaengen — sonst verschwaende die Auswahl beim Oeffnen still.
    final known = library.map((route) => route.id).toSet();
    final missing = widget.initialSelection
        .where((route) => !known.contains(route.id))
        .toList();

    setState(() {
      _library = [...missing, ...library];
      // IDs ohne zugehoerige Route koennen nicht dargestellt werden.
      final available = _library.map((route) => route.id).toSet();
      _selected = _selected.where(available.contains).toList();
      _loading = false;
    });
  }

  void _toggle(SavedRoute route) {
    setState(() {
      if (_selected.contains(route.id)) {
        _selected.remove(route.id);
        return;
      }
      if (_selected.length >= FavoriteRoutesService.maxFavorites) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Maximal 3 Lieblingsrouten. Nimm zuerst eine wieder raus.',
            ),
          ),
        );
        return;
      }
      _selected.add(route.id);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final success = await FavoriteRoutesService.setFavorites(_selected);
    if (!mounted) return;

    if (!success) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speichern fehlgeschlagen. Bitte nochmal versuchen.'),
        ),
      );
      return;
    }

    // In der gewaehlten Reihenfolge zurueckgeben — das Profil zeigt sie
    // sofort so an, ohne auf einen Neu-Ladevorgang zu warten.
    final byId = {for (final route in _library) route.id: route};
    Navigator.pop(context, [
      for (final id in _selected)
        if (byId[id] != null) byId[id]!,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F1218),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              _buildHeader(accent),
              const Divider(height: 1, color: Color(0xFF232833)),
              Expanded(child: _buildBody(accent, scrollController)),
              _buildFooter(accent),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite_rounded, color: accent, size: 19),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Lieblingsrouten wählen',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${_selected.length}/${FavoriteRoutesService.maxFavorites}',
                style: TextStyle(
                  color: accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Die Reihenfolge deiner Auswahl ist die Reihenfolge im Profil.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(Color accent, ScrollController scrollController) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: accent));
    }
    if (_library.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.route_rounded,
              color: Colors.white.withValues(alpha: 0.25),
              size: 44,
            ),
            const SizedBox(height: 14),
            const Text(
              'Noch keine gespeicherten Routen',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Fahr eine Route und speichere sie. Danach kannst du sie hier '
              'an dein Profil pinnen.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      itemCount: _library.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final route = _library[index];
        final rank = _selected.indexOf(route.id);
        return _buildRouteTile(route: route, rank: rank, accent: accent);
      },
    );
  }

  Widget _buildRouteTile({
    required SavedRoute route,
    required int rank,
    required Color accent,
  }) {
    final isSelected = rank >= 0;
    final name = route.name?.trim();
    final title = (name != null && name.isNotEmpty)
        ? name
        : '${route.styleEmoji} ${route.displayStyleLabel}';

    return InkWell(
      onTap: _saving ? null : () => _toggle(route),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF161A22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accent : Colors.white.withValues(alpha: 0.07),
            width: isSelected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 74,
                height: 60,
                child: FavoriteRoutePreview(route: route, accent: accent),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${route.formattedDistance} · '
                    '${route.durationLabelOrEstimate} · '
                    '${route.displayStyleLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _buildSelectionMark(rank: rank, accent: accent),
          ],
        ),
      ),
    );
  }

  /// Zeigt den PLATZ statt eines Hakens — die Reihenfolge ist Teil der
  /// Auswahl, und nur so sieht man beim Tippen sofort, worauf sie landet.
  Widget _buildSelectionMark({required int rank, required Color accent}) {
    if (rank < 0) {
      return Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
      );
    }
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
      child: Text(
        '${rank + 1}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildFooter(Color accent) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Abbrechen',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _selected.isEmpty
                            ? 'Auswahl leeren'
                            : 'Auswahl speichern',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
