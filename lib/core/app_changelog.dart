/// Was sich pro Version geaendert hat — in der Sprache der Fahrer, nicht in
/// der Sprache des Repos.
///
/// 2026-08-09 (vucko): „Nach jedem Update soll ein Update-Log kommen, damit
/// die Leute wissen, was sich getaendert hat." Der Katalog liegt bewusst im
/// Code und nicht in der Datenbank: Ein Update-Hinweis muss auch dann
/// erscheinen, wenn das Handy gerade kein Netz hat.
///
/// PFLEGE: Bei jedem Release oben einen neuen Eintrag ergaenzen. Die Version
/// muss exakt der `version:` aus der pubspec.yaml entsprechen (ohne die
/// Build-Nummer nach dem `+`), sonst findet [AppChangelog.fuerVersion] sie
/// nicht und es erscheint kein Hinweis.
library;

class ChangelogEintrag {
  const ChangelogEintrag({
    required this.version,
    required this.titel,
    required this.punkte,
  });

  /// Marketing-Version ohne Build-Nummer, z. B. `1.5.10`.
  final String version;

  /// Eine Zeile, die den Kern des Updates auf den Punkt bringt.
  final String titel;

  /// Die einzelnen Neuerungen. Kurz, konkret, aus Nutzersicht.
  final List<String> punkte;
}

class AppChangelog {
  AppChangelog._();

  /// Neueste Version zuerst.
  static const List<ChangelogEintrag> eintraege = <ChangelogEintrag>[
    ChangelogEintrag(
      version: '1.5.11',
      titel: 'Bessere Routen, Gruppenfahrten und Rueckmeldungen',
      punkte: <String>[
        'Die Fahrstile liefern wieder wirklich unterschiedliche Routen: '
            'Kurvenjagd sucht die kurvigen Strecken, der Sportmodus die '
            'fluessigen, die Abendrunde die gemuetlichen.',
        'A nach B mit Umweg: klein ist rund doppelt so lang wie der direkte Weg, '
            'mittel dreifach, gross vierfach. Aus 20 km werden 40, 60 oder 80 km.',
        'Gruppe einrichten: Die Karte laesst sich jetzt frei bewegen und das '
            'Formular einklappen — du siehst die Route, bevor ihr losfahrt.',
        'Fahrer und Mitfahrer sind getrennt: Wer als Mitfahrer eingetragen ist, '
            'erscheint nicht mehr als eigenes Auto auf der Karte.',
        'Verfahren in der Gruppe: Statt ratlos stehenzubleiben bekommst du die '
            'Wahl — zurueck zur Gruppe, Gruppenroute uebernehmen oder eigene Route.',
        'Die Kamera dreht sich waehrend der Gruppenfahrt nicht mehr wild.',
        'Neu in den Einstellungen: Rueckmeldung schicken — mit Foto, direkt an uns.',
        'Kurven werden jetzt ueberall gleich und genau gezaehlt.',
      ],
    ),
  ];

  static ChangelogEintrag? fuerVersion(String version) {
    for (final eintrag in eintraege) {
      if (eintrag.version == version) return eintrag;
    }
    return null;
  }
}
