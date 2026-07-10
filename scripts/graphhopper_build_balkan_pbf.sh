#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# GraphHopper Balkan-Erweiterung — Karten-PBF bauen
# 2026-07-09 (vucko): Der aktuelle Graph (`dach-italy-balkan.osm.pbf`) deckt nur
# DACH + IT + SI + HR (+teils BA) ab. RS/ME/MK/AL/XK/BG/RO/GR fehlen → dort kam
# gar keine Route. Dieses Skript lädt die FEHLENDEN Länder von Geofabrik und
# merged sie mit dem bestehenden Extract zu EINER PBF, die ganz Südosteuropa
# abdeckt. osmium merge dedupliziert Objekte an den Grenzen automatisch.
#
# Danach: siehe docs/GRAPHHOPPER_BALKAN_EXPANSION.md für den Reimport auf den PCs.
#
# Voraussetzung: osmium (`brew install osmium-tool` / `apt install osmium-tool`),
# ~10 GB freier Platz, ~3-4 GB Download.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

WORK="${1:-$HOME/graphhopper_balkan_build}"
BASE_PBF="${BASE_PBF:-$HOME/graphhopper/data/dach-italy-balkan.osm.pbf}"  # bestehender Extract (von PC kopieren falls lokal gebaut)
OUT_PBF="${OUT_PBF:-$WORK/dach-balkan-full.osm.pbf}"
GEOFABRIK="https://download.geofabrik.de/europe"

# Fehlende Balkan-Länder (alles, was der bisherige Extract nicht abdeckt)
COUNTRIES=(serbia bulgaria romania greece albania macedonia montenegro kosovo)

command -v osmium >/dev/null || { echo "❌ osmium fehlt — brew install osmium-tool"; exit 1; }
mkdir -p "$WORK"
cd "$WORK"

echo "▶ 1/3  Fehlende Länder von Geofabrik laden …"
DL=()
for c in "${COUNTRIES[@]}"; do
  f="$WORK/${c}-latest.osm.pbf"
  if [[ -s "$f" ]]; then echo "  ✓ $c bereits da"; else
    echo "  ↓ $c"; curl -fL --retry 3 -o "$f" "$GEOFABRIK/${c}-latest.osm.pbf"
  fi
  DL+=("$f")
done

echo "▶ 2/3  Basis-Extract prüfen …"
if [[ ! -s "$BASE_PBF" ]]; then
  echo "  ⚠ $BASE_PBF nicht gefunden — hole ihn zuerst vom PC:"
  echo "     scp vucko1@vucko2:~/graphhopper/data/dach-italy-balkan.osm.pbf \"$BASE_PBF\""
  echo "  (oder BASE_PBF=… setzen). Alternativ ganz Südosteuropa nur aus den Länder-PBFs bauen —"
  echo "   dann fehlt aber DACH; für den Voll-Graph MUSS der Basis-Extract dabei sein.)"
  exit 1
fi

echo "▶ 3/3  Merge → $OUT_PBF  (osmium dedupliziert Grenz-Overlaps automatisch) …"
osmium merge --overwrite -o "$OUT_PBF" "$BASE_PBF" "${DL[@]}"

echo ""
echo "✅ Fertig: $OUT_PBF ($(du -h "$OUT_PBF" | cut -f1))"
echo "   Nächster Schritt: docs/GRAPHHOPPER_BALKAN_EXPANSION.md → Reimport auf PC2 (+ PC1)."
echo "   Kurz: PBF auf den PC kopieren, config.yml datareader.file darauf zeigen,"
echo "   graph-cache LÖSCHEN, Service neu starten (GH re-importiert dann ~1-3 h)."
