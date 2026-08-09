/**
 * Baut aus dashboard.html + dashboard.js + logo.png eine einzelne Datei
 * monitor.html, die auf Cloudflare R2 hochgeladen wird.
 *
 * WARUM EINE EINZELNE DATEI: Auf R2 liegt nur diese eine Seite. Sie darf
 * nichts nachladen, weder Skript noch Bild noch Schriftart. Ein Dashboard,
 * das ein fremdes CDN anfragt, kann von dort ausfallen oder mitgelesen
 * werden. Deshalb wird das JavaScript eingebettet und das Logo als
 * data:-URI eingesetzt.
 *
 * WARUM NICHT MEHR baue_seite.ts: Die Vorgaengerin hat die ganze Seite als
 * TypeScript-Template-Literal gehalten. Jedes Anfuehrungszeichen im
 * eingebetteten JavaScript musste dort \\" geschrieben werden, ein einzelnes
 * \" brach die ausgelieferte Seite lautlos. Dazu durfte kein Backtick und
 * kein ${...} vorkommen. Jetzt sind es normale Dateien.
 *
 * Aufruf:  node supabase/functions/admin-monitor/baue_dashboard.mjs
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const hier = dirname(fileURLToPath(import.meta.url));
const API = 'https://tlcfaxvvqzobmzwvfnvb.supabase.co/functions/v1/admin-monitor';

const html = readFileSync(join(hier, 'dashboard.html'), 'utf8');
const js = readFileSync(join(hier, 'dashboard.js'), 'utf8');
const logo = readFileSync(join(hier, 'logo.png')).toString('base64');

// Ein </script> im JavaScript wuerde den umgebenden Block beenden. Kommt
// aktuell nicht vor, aber die Zeile hier kostet nichts und verhindert, dass
// eine spaetere Aenderung die Seite zerlegt.
const jsSicher = js
  .replaceAll('__API_URL__', API)
  .replaceAll('</script', '<\\/script');

let out = html
  .replaceAll('__LOGO__', 'data:image/png;base64,' + logo)
  .replace('<script src="__SKRIPT__"></script>', '<script>\n' + jsSicher + '\n</script>');

const offen = out.match(/__[A-Z_]+__/g) || [];
if (offen.length) {
  console.error('FEHLER: nicht ersetzte Platzhalter:', [...new Set(offen)]);
  process.exit(1);
}
if (out.includes('__SKRIPT__') || !out.includes('<script>')) {
  console.error('FEHLER: das Skript wurde nicht eingebettet.');
  process.exit(1);
}

const ziel = join(hier, 'monitor.html');
writeFileSync(ziel, out, 'utf8');

console.log('Geschrieben:', ziel);
console.log('Groesse:', (out.length / 1024).toFixed(1), 'kB');
console.log('Logo:', (logo.length / 1024).toFixed(1), 'kB base64');
