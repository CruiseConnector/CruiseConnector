/// 2026-05-24 (vucko): Vereinfachter OSM-Opening-Hours-Parser.
///
/// OSM-Format ist sehr komplex (https://wiki.openstreetmap.org/wiki/Key:opening_hours).
/// Wir handeln nur die häufigsten Fälle die in DACH für Tankstellen +
/// Restaurants vorkommen:
///   - `24/7` → immer offen
///   - `Mo-Fr 06:00-22:00`
///   - `Mo-Fr 06:00-22:00; Sa,Su 08:00-20:00`
///   - `Mo-Su 00:00-24:00`
///   - `Mo-Sa 08:00-20:00; PH off`  (PH=Public Holiday)
///   - `Mo,Tu,We,Th,Fr 06:00-22:00`
///
/// Liefert:
///   - aktuelle Status (offen/geschlossen/schließt-bald)
///   - schöne Wochentag-Liste für UI
class OpeningHoursParser {
  /// Wochentage in deutscher Reihenfolge (Mo = 1 in DateTime.weekday).
  static const _osmDayMap = {
    'Mo': 1, 'Tu': 2, 'We': 3, 'Th': 4, 'Fr': 5, 'Sa': 6, 'Su': 7,
  };

  static const _germanDayShort = {
    1: 'Mo', 2: 'Di', 3: 'Mi', 4: 'Do', 5: 'Fr', 6: 'Sa', 7: 'So',
  };

  /// Parsed das OSM-`opening_hours` Tag. Wirft NIE — bei Parse-Error
  /// gibt's eine [OpeningHoursInfo] mit `parseFailed=true`.
  static OpeningHoursInfo parse(String? osmString, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final raw = osmString?.trim();
    if (raw == null || raw.isEmpty) {
      return const OpeningHoursInfo._(
        rawString: '',
        is247: false,
        parseFailed: true,
        status: OpenStatus.unknown,
        todayLabel: 'Keine Angabe',
        weekRanges: {},
      );
    }
    // Spezialfall: 24/7
    if (RegExp(r'^\s*24/7\s*$').hasMatch(raw)) {
      return OpeningHoursInfo._(
        rawString: raw,
        is247: true,
        parseFailed: false,
        status: OpenStatus.open24_7,
        todayLabel: 'Rund um die Uhr',
        weekRanges: {
          for (var d = 1; d <= 7; d++) d: const [_TimeRange(0, 0, 24, 0)],
        },
      );
    }

    // Sections trennen (durch `;` oder `,` zwischen Day-Specs).
    // OSM trennt Rules mit `;`. Wir splitten und parsen jede Rule.
    final rules = raw.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty);
    final weekRanges = <int, List<_TimeRange>>{};
    var parseFailed = false;
    for (final rule in rules) {
      // "PH off" / "PH closed" überspringen — wir kennen Feiertage nicht.
      if (rule.toLowerCase().contains('ph')) continue;
      // "off" / "closed" am Ende = expliziter Block — überspringen.
      if (rule.toLowerCase().endsWith('off') ||
          rule.toLowerCase().endsWith('closed')) {
        continue;
      }
      try {
        // Format: "Mo-Fr 06:00-22:00" oder "Mo,We,Fr 08:00-18:00"
        final parts = rule.split(RegExp(r'\s+'));
        if (parts.length < 2) {
          parseFailed = true;
          continue;
        }
        final daysSpec = parts.first;
        final timeSpecs = parts.sublist(1).join(' ');
        final days = _parseDaySpec(daysSpec);
        final times = _parseTimeSpec(timeSpecs);
        if (days.isEmpty || times.isEmpty) {
          parseFailed = true;
          continue;
        }
        for (final d in days) {
          weekRanges.putIfAbsent(d, () => []).addAll(times);
        }
      } catch (_) {
        parseFailed = true;
      }
    }

    final todayIdx = reference.weekday;
    final todayRanges = weekRanges[todayIdx] ?? const <_TimeRange>[];
    final nowMin = reference.hour * 60 + reference.minute;

    OpenStatus status;
    String todayLabel;
    if (todayRanges.isEmpty) {
      status = OpenStatus.closedToday;
      todayLabel = 'Heute geschlossen';
    } else {
      // Aktiver Range jetzt?
      _TimeRange? activeRange;
      _TimeRange? nextRange;
      for (final r in todayRanges) {
        if (nowMin >= r.startMin && nowMin < r.endMin) {
          activeRange = r;
          break;
        }
        if (nowMin < r.startMin && (nextRange == null || r.startMin < nextRange.startMin)) {
          nextRange = r;
        }
      }
      if (activeRange != null) {
        final minsUntilClose = activeRange.endMin - nowMin;
        if (minsUntilClose <= 30) {
          status = OpenStatus.closingSoon;
          todayLabel = 'Schließt in $minsUntilClose Min';
        } else {
          status = OpenStatus.open;
          todayLabel = 'Offen bis ${_fmtTime(activeRange.endMin)}';
        }
      } else if (nextRange != null) {
        status = OpenStatus.closedNow;
        todayLabel = 'Öffnet um ${_fmtTime(nextRange.startMin)}';
      } else {
        status = OpenStatus.closedNow;
        todayLabel = 'Geschlossen';
      }
    }

    return OpeningHoursInfo._(
      rawString: raw,
      is247: false,
      parseFailed: parseFailed && weekRanges.isEmpty,
      status: status,
      todayLabel: todayLabel,
      weekRanges: weekRanges,
    );
  }

  static List<int> _parseDaySpec(String spec) {
    final days = <int>{};
    // Mehrere Bereiche durch Komma getrennt: "Mo-Fr,Su" oder "Mo,We"
    for (final part in spec.split(',')) {
      final p = part.trim();
      if (p.contains('-')) {
        final ends = p.split('-');
        if (ends.length != 2) continue;
        final from = _osmDayMap[ends[0]];
        final to = _osmDayMap[ends[1]];
        if (from == null || to == null) continue;
        var i = from;
        while (true) {
          days.add(i);
          if (i == to) break;
          i = i == 7 ? 1 : i + 1;
        }
      } else {
        final d = _osmDayMap[p];
        if (d != null) days.add(d);
      }
    }
    return days.toList()..sort();
  }

  static List<_TimeRange> _parseTimeSpec(String spec) {
    final ranges = <_TimeRange>[];
    // Mehrere Zeiträume getrennt durch Komma: "08:00-12:00,14:00-18:00"
    for (final part in spec.split(',')) {
      final m = RegExp(r'(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})')
          .firstMatch(part.trim());
      if (m == null) continue;
      final sh = int.parse(m.group(1)!);
      final sm = int.parse(m.group(2)!);
      var eh = int.parse(m.group(3)!);
      final em = int.parse(m.group(4)!);
      // 24:00 als Mitternacht behandeln (häufig in OSM)
      if (eh == 24 && em == 0) eh = 24;
      ranges.add(_TimeRange(sh, sm, eh, em));
    }
    return ranges;
  }

  static String _fmtTime(int totalMin) {
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// Renderbare Wochentag-Liste, sortiert ab Heute.
  /// `[("Heute", "06:00-22:00"), ("Di", "06:00-22:00"), ...]`
  // ignore: library_private_types_in_public_api
  static List<({String day, String hours, bool isToday})> renderWeekList(
    OpeningHoursInfo info, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final todayIdx = reference.weekday;
    final out = <({String day, String hours, bool isToday})>[];
    for (var offset = 0; offset < 7; offset++) {
      var dayIdx = todayIdx + offset;
      if (dayIdx > 7) dayIdx -= 7;
      final ranges = info.weekRanges[dayIdx] ?? const <_TimeRange>[];
      final label = offset == 0 ? 'Heute' : _germanDayShort[dayIdx]!;
      final hoursText = ranges.isEmpty
          ? 'Geschlossen'
          : ranges
              .map((r) => '${_fmtTime(r.startMin)}–${_fmtTime(r.endMin)}')
              .join(', ');
      out.add((day: label, hours: hoursText, isToday: offset == 0));
    }
    return out;
  }
}

class _TimeRange {
  final int startMin;
  final int endMin;
  const _TimeRange(int sh, int sm, int eh, int em)
      : startMin = sh * 60 + sm,
        endMin = eh * 60 + em;
}

enum OpenStatus {
  open,           // offen, schließt nicht in <30 min
  closingSoon,    // offen, schließt in 0-30 min
  closedNow,      // jetzt zu, öffnet später
  closedToday,    // den ganzen Tag zu
  open24_7,       // rund um die Uhr
  unknown,        // keine Daten
}

class OpeningHoursInfo {
  final String rawString;
  final bool is247;
  final bool parseFailed;
  final OpenStatus status;
  final String todayLabel;
  // ignore: library_private_types_in_public_api
  final Map<int, List<_TimeRange>> weekRanges;

  const OpeningHoursInfo._({
    required this.rawString,
    required this.is247,
    required this.parseFailed,
    required this.status,
    required this.todayLabel,
    required this.weekRanges,
  });

  bool get isOpenNow =>
      status == OpenStatus.open ||
      status == OpenStatus.closingSoon ||
      status == OpenStatus.open24_7;

  bool get isClosingSoon => status == OpenStatus.closingSoon;
}
