import 'package:flutter/material.dart';

import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/domain/models/user_drive_session.dart';
import 'package:cruise_connect/presentation/pages/ride_detail_page.dart';

/// Alle Fahrten des Nutzers, nicht nur die letzten fuenf.
///
/// 2026-09-01 (Vucko: „routen die man gefahren ist im nachhinein noch
/// speichern kann oder ganz wichtig fotos hinzufuegen kann"):
///
/// Beides gab es auf der Fahrten-Detailseite laengst — Fotos hinzufuegen,
/// ersetzen und loeschen. Erreichbar war sie aber nur ueber „Letzte Fahrten"
/// in der Auswertung, und die zeigt bewusst nur fuenf Eintraege. Alles
/// Aeltere war schlicht nicht mehr aufrufbar, egal wie sehr man suchte.
///
/// Diese Seite aendert an der Uebersicht nichts. Sie ist der Weg zu allem
/// dahinter.
class AlleFahrtenPage extends StatelessWidget {
  const AlleFahrtenPage({super.key, required this.fahrten});

  final List<UserDriveSession> fahrten;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final sortiert = [...fahrten]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          sortiert.length == 1 ? 'Eine Fahrt' : '${sortiert.length} Fahrten',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: sortiert.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Hier stehen deine Fahrten, sobald du losgefahren bist.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFA0AEC0), fontSize: 14),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: sortiert.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) =>
                  _FahrtZeile(fahrt: sortiert[i], accent: accent),
            ),
    );
  }
}

class _FahrtZeile extends StatelessWidget {
  const _FahrtZeile({required this.fahrt, required this.accent});

  final UserDriveSession fahrt;
  final Color accent;

  static const _monate = [
    'Jan', 'Feb', 'März', 'Apr', 'Mai', 'Juni',
    'Juli', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
  ];

  String get _datum {
    final l = fahrt.createdAt.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '${l.day}. ${_monate[l.month - 1]} ${l.year}, $hh:$mm';
  }

  String get _dauer {
    final min = (fahrt.durationSeconds / 60).round();
    if (min < 60) return '$min min';
    final h = min ~/ 60;
    final r = min % 60;
    return r == 0 ? '$h h' : '$h h $r min';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RideDetailPage(session: fahrt)),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Row(
            children: [
              // Ein Foto sagt mehr als jede Zeile Text. Gibt es keines, steht
              // dort das Streckensymbol.
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: fahrt.photoUrl != null && fahrt.photoUrl!.isNotEmpty
                      ? Image.network(
                          fahrt.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _Platzhalter(accent: accent),
                        )
                      : _Platzhalter(accent: accent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _datum,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${fahrt.distanceKm.toStringAsFixed(1)} km · $_dauer'
                      '${fahrt.topSpeedKmh != null ? ' · ${fahrt.topSpeedKmh!.round()} km/h' : ''}',
                      style: const TextStyle(
                        color: Color(0xFFA0AEC0),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (fahrt.photoUrl != null && fahrt.photoUrl!.isNotEmpty)
                Icon(
                  Icons.photo_camera_rounded,
                  size: 16,
                  color: accent.withValues(alpha: 0.8),
                ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF6B7280),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Platzhalter extends StatelessWidget {
  const _Platzhalter({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: accent.withValues(alpha: 0.12),
      child: Icon(Icons.route_rounded, color: accent, size: 24),
    );
  }
}
