// Laesst Deno das Template-Literal AUSWERTEN, statt es mit regulaeren
// Ausdruecken herauszuschneiden. Der erste Versuch hat dabei die
// Maskierungen zerstoert (\" wurde zu \\") und das Skript unbrauchbar
// gemacht.
import { SEITE } from './seite.ts';
const anon = Deno.args[0];
const html = SEITE
  .replaceAll('__SUPABASE_URL__', 'https://tlcfaxvvqzobmzwvfnvb.supabase.co')
  .replaceAll('__ANON_KEY__', anon)
  .replace('fetch(location.pathname,{',
           'fetch("https://tlcfaxvvqzobmzwvfnvb.supabase.co/functions/v1/admin-monitor",{');
await Deno.writeTextFile('/tmp/monitor_neu.html', html);
console.log('Zeichen:', html.length);
console.log('Offene Platzhalter:', (html.match(/__(SUPABASE_URL|ANON_KEY)__/g) || []).length);
console.log('Doppelte Maskierung (\\\\"):', (html.match(/\\\\"/g) || []).length);
