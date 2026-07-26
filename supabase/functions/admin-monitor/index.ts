// ─────────────────────────────────────────────────────────────────────────────
// admin-monitor — Live-Monitoring-Dashboard für CruiseConnect.
//
// Serviert eine self-contained HTML-Seite mit Live-Kennzahlen (Nutzung, Routing,
// Infrastruktur, Community, Werbung/Abo). Läuft server-seitig mit service_role
// (umgeht RLS), Zugriff ist per ?token=<MONITOR_TOKEN> geschützt — den Link kann
// Vucko einfach mit Luca teilen. config.toml: verify_jwt = false.
//
// Endpunkte:
//   GET /admin-monitor?token=XXX          -> HTML-Dashboard
//   GET /admin-monitor?token=XXX&data=1   -> JSON (Metriken + Infra-Ping)
// ─────────────────────────────────────────────────────────────────────────────
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const MONITOR_TOKEN = Deno.env.get('MONITOR_TOKEN') ?? '';
// Not-Aus (2026-07-21): auf Vuckos Anweisung per Incident deaktiviert, bis
// die Ursache eines "es ist schon wieder passiert"-Vorfalls geklärt ist —
// unterbindet JEDE der 5 schweren RPCs, egal wie viele Dashboards offen sind.
// Reaktivieren: `supabase secrets set MONITOR_PAUSED=false` (oder Secret löschen).
const MONITOR_PAUSED = (Deno.env.get('MONITOR_PAUSED') ?? '').toLowerCase() === 'true';

// GraphHopper-Funnels (öffentliche /health)
const PC2_HEALTH = 'https://vucko2-hp-prodesk-600-g5-desktop-mini.taildddd94.ts.net/health';
const PC1_HEALTH = 'https://vucko.taildddd94.ts.net/health';

async function ping(url: string): Promise<{ up: boolean; ms: number | null }> {
  const t0 = Date.now();
  try {
    const r = await fetch(url, { signal: AbortSignal.timeout(6000) });
    return { up: r.ok, ms: Date.now() - t0 };
  } catch {
    return { up: false, ms: null };
  }
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const token = url.searchParams.get('token') ?? '';

  if (!MONITOR_TOKEN) {
    return html('<h1>Nicht konfiguriert</h1><p>MONITOR_TOKEN-Secret fehlt.</p>', 500);
  }
  if (token !== MONITOR_TOKEN) {
    return html('<div style="font-family:system-ui;max-width:420px;margin:15vh auto;text-align:center;color:#e8eaed"><div style="font-size:40px">🔒</div><h1 style="font-weight:650">Zugriff geschützt</h1><p style="color:#8a929e">Dieser Monitoring-Link braucht ein gültiges Token.</p></div>', 401);
  }

  if (url.searchParams.get('data') === '1') {
    if (MONITOR_PAUSED) {
      // Kein einziger RPC-Call, keine DB-Anfrage — reine statische Antwort.
      return new Response(
        JSON.stringify({
          metrics: null, history: null, today: null, compare: null, analytics: null,
          error: 'Monitoring pausiert (Wartung nach Incident) — RPC-Abfragen deaktiviert.',
          infra: { pc2: { up: false, ms: null }, pc1: { up: false, ms: null } },
        }),
        { headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } },
      );
    }
    // "force=1" (manueller ⟳-Button) bypasst den Halbtags-Slot bewusst NICHT
    // mehr — Vuckos Vorgabe "0 Uhr, 12 Uhr, mehr nicht" gilt ausnahmslos,
    // auch für Klicks. Der Button liefert einfach den aktuellen Cache-Stand.
    const body = await getMonitorData();
    return new Response(body, {
      headers: {
        'content-type': 'application/json',
        // CDN-Cache (Supabase läuft hinter Cloudflare): s-maxage lässt das CDN
        // die Antwort teilen → ALLE Dashboards zusammen erzeugen so gut wie
        // keine RPC-Last, egal wie viele offen sind. Der Browser selbst
        // cacht nicht (max-age=0), damit der Fresh-Ticker ehrlich bleibt.
        'cache-control': 'public, max-age=0, s-maxage=3300',
        'access-control-allow-origin': '*',
      },
    });
  }

  return html(PAGE, 200);
});

// ── Daten-Beschaffung mit Cache + Single-Flight (2026-07-19) ────────────────
// WARUM: Jeder offene Dashboard-Viewer (Browser-Tabs, Desktop-Apps, Handy-App,
// Kollege) pollte alle 30 s → JEDER Poll feuerte 5 schwere RPCs. Bei mehreren
// Viewern hat sich die DB damit selbst überlastet (522-Sturm in den API-Logs,
// „Unhealthy"-Status). Jetzt: EIN RPC-Rundlauf pro ~25 s für ALLE Viewer
// (Modul-Cache), parallele Anfragen teilen sich denselben Refresh
// (Single-Flight), und bei DB-Problemen wird der letzte gute Stand mit
// stale-Markierung ausgeliefert statt weiter zu hämmern. RPCs haben 12-s-
// Abort, damit keine Anfrage-Leichen die DB weiter belasten.
// Genau 2 echte Aktualisierungen pro Tag (Vuckos Vorgabe nach dem Incident
// vom 21.07.: "einmal um 0 Uhr, einmal um 12 Uhr, mehr nicht") — statt einer
// Alters-basierten TTL (die bei vielen offenen Dashboards trotzdem beliebig
// oft neu zünden könnte) hängt die Cache-Gültigkeit jetzt an einer festen
// Kalender-"Halbtags-Slot"-ID (Europe/Vienna, DST-sicher via Intl). Erst wenn
// der Slot wechselt (Uhrzeit kreuzt 00:00 oder 12:00 in Wien), wird EIN
// einziges Mal neu von der DB geholt — egal wie oft/viele Clients pollen.
const FAIL_COOLDOWN_MS = 30_000;
let _cacheBody: string | null = null;
let _cacheSlot = '';
let _inflight: Promise<string> | null = null;
let _lastFailBody: string | null = null;
let _lastFailAt = 0;

function viennaSlotKey(d = new Date()): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Vienna',
    year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', hourCycle: 'h23',
  }).formatToParts(d);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? '';
  const hour = Number(get('hour'));
  const half = hour < 12 ? 'am' : 'pm'; // ab 00:00 -> 'am'-Slot, ab 12:00 -> 'pm'-Slot
  return `${get('year')}-${get('month')}-${get('day')}-${half}`;
}

async function getMonitorData(): Promise<string> {
  if (_cacheBody && _cacheSlot === viennaSlotKey()) return _cacheBody;
  // Fehler-Cooldown: Wenn die DB gerade down ist, nicht bei jedem Poll eine
  // neue RPC-Salve zünden — letzten Fehlerstand ausliefern, max. ~2 echte
  // Versuche pro Minute, egal wie viele Dashboards offen sind.
  if (!_cacheBody && _lastFailBody && Date.now() - _lastFailAt < FAIL_COOLDOWN_MS) {
    return _lastFailBody;
  }
  if (_inflight) {
    // Refresh läuft schon: alten Stand sofort liefern statt mitzuwarten,
    // sonst stauen sich bei langsamer DB die Requests.
    if (_cacheBody) return _cacheBody;
    return _inflight;
  }
  _inflight = refreshMonitorData().finally(() => {
    _inflight = null;
  });
  if (_cacheBody) return _cacheBody; // stale sofort, frisch kommt beim nächsten Poll
  return _inflight;
}

// Circuit-Breaker: winziger, 3 s begrenzter Probe-Query. Schlägt er fehl,
// werden die 5 schweren RPCs GAR NICHT gefeuert — die kranke DB bekommt Ruhe
// zum Erholen, statt von jedem Dashboard-Poll weiter gepinnt zu werden.
// Funktioniert pro Isolate ohne geteilten Zustand.
async function dbProbe(): Promise<boolean> {
  try {
    const r = await fetch(
      `${SUPABASE_URL}/rest/v1/communities?select=id&limit=1`,
      {
        headers: { apikey: SERVICE_ROLE, authorization: `Bearer ${SERVICE_ROLE}` },
        signal: AbortSignal.timeout(3000),
      },
    );
    return r.ok;
  } catch (_) {
    return false;
  }
}

async function refreshMonitorData(): Promise<string> {
  if (!(await dbProbe())) {
    if (_cacheBody) return markStale(_cacheBody);
    _lastFailBody = JSON.stringify({
      metrics: null, history: null, today: null, compare: null, analytics: null,
      error: 'Datenbank erholt sich gerade (Circuit-Breaker aktiv) — nächster Versuch in Kürze.',
      infra: { pc2: { up: false, ms: null }, pc1: { up: false, ms: null } },
    });
    _lastFailAt = Date.now();
    return _lastFailBody;
  }
  const supa = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });
  const rpc = (name: string) =>
    supa.rpc(name).abortSignal(AbortSignal.timeout(12_000));
  try {
    const [{ data, error }, hist, today, compare, analytics, pc2, pc1] = await Promise.all([
      rpc('admin_monitor_metrics'),
      rpc('admin_monitor_history'),
      rpc('admin_monitor_today'),
      rpc('admin_monitor_compare'),
      rpc('admin_monitor_analytics'),
      ping(PC2_HEALTH),
      ping(PC1_HEALTH),
    ]);
    const body = JSON.stringify({
      metrics: error ? null : data,
      history: hist.error ? null : hist.data,
      today: today.error ? null : today.data,
      compare: compare.error ? null : compare.data,
      analytics: analytics.error ? null : analytics.data,
      error: error?.message ?? null,
      infra: { pc2, pc1 },
      cached_at: new Date().toISOString(),
    });
    // Nur brauchbare Antworten cachen (metrics vorhanden) — sonst stale behalten.
    if (!error) {
      _cacheBody = body;
      _cacheSlot = viennaSlotKey();
      return body;
    }
    if (_cacheBody) return markStale(_cacheBody);
    _lastFailBody = body;
    _lastFailAt = Date.now();
    return body;
  } catch (e) {
    if (_cacheBody) return markStale(_cacheBody);
    _lastFailBody = JSON.stringify({
      metrics: null, history: null, today: null, compare: null, analytics: null,
      error: `DB nicht erreichbar: ${e instanceof Error ? e.message : e}`,
      infra: { pc2: { up: false, ms: null }, pc1: { up: false, ms: null } },
    });
    _lastFailAt = Date.now();
    return _lastFailBody;
  }
}

function markStale(body: string): string {
  try {
    const o = JSON.parse(body);
    o.stale = true;
    return JSON.stringify(o);
  } catch (_) {
    return body;
  }
}

function html(body: string, status = 200): Response {
  return new Response(body, { status, headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });
}

// ── Dashboard-HTML (self-contained; Client-JS liest Token aus der eigenen URL) ──
const PAGE = `<!doctype html><html lang="de"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>CruiseConnect · Monitoring</title>
<style>
  :root{
    --bg:#0e1116; --surface:#161b22; --surface2:#1c232c; --line:#242c37;
    --txt:#e9edf2; --muted:#8b95a3; --dim:#5b6675;
    --accent:#ff7a1a; --accent-dim:#3a2416;
    --ok:#3fb950; --ok-dim:#12261a; --bad:#f85149; --bad-dim:#2a1516; --warn:#d29922;
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--txt);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased;font-variant-numeric:tabular-nums}
  .wrap{max-width:1120px;margin:0 auto;padding:20px 18px 60px}
  header{display:flex;align-items:center;gap:12px;flex-wrap:wrap;padding:6px 2px 18px}
  .logo{width:30px;height:30px;border-radius:8px;background:linear-gradient(135deg,var(--accent),#ffb066);display:grid;place-items:center;font-size:17px}
  h1{font-size:17px;font-weight:680;margin:0;letter-spacing:.2px}
  .sub{color:var(--muted);font-size:12.5px}
  .live{margin-left:auto;display:flex;align-items:center;gap:14px;color:var(--muted);font-size:12px}
  .dot{width:8px;height:8px;border-radius:50%;background:var(--ok);box-shadow:0 0 0 0 rgba(63,185,80,.5);animation:pulse 2s infinite}
  @keyframes pulse{0%{box-shadow:0 0 0 0 rgba(63,185,80,.5)}70%{box-shadow:0 0 0 7px rgba(63,185,80,0)}100%{box-shadow:0 0 0 0 rgba(63,185,80,0)}}
  @media (prefers-reduced-motion){.dot{animation:none}}
  h2{font-size:12px;font-weight:640;letter-spacing:.9px;text-transform:uppercase;color:var(--dim);margin:26px 2px 11px}
  .grid{display:grid;gap:11px}
  .g4{grid-template-columns:repeat(4,1fr)} .g3{grid-template-columns:repeat(3,1fr)} .g2{grid-template-columns:repeat(2,1fr)}
  @media (max-width:760px){.g4{grid-template-columns:repeat(2,1fr)}.g3{grid-template-columns:repeat(2,1fr)}.g2{grid-template-columns:1fr}}
  @media (max-width:420px){.g4,.g3{grid-template-columns:1fr}}
  .card{background:var(--surface);border:1px solid var(--line);border-radius:13px;padding:14px 15px}
  .kpi .label{color:var(--muted);font-size:12px;font-weight:520;margin-bottom:7px}
  .kpi .val{font-size:27px;font-weight:700;line-height:1;letter-spacing:-.4px}
  .kpi .val small{font-size:14px;color:var(--muted);font-weight:600;margin-left:3px}
  .kpi .foot{margin-top:8px;font-size:12px;color:var(--muted)}
  .up{color:var(--ok)} .down{color:var(--bad)} .accent{color:var(--accent)}
  .pill{display:inline-flex;align-items:center;gap:7px;padding:4px 10px;border-radius:999px;font-size:12.5px;font-weight:600}
  .pill.ok{background:var(--ok-dim);color:var(--ok)} .pill.bad{background:var(--bad-dim);color:var(--bad)}
  .infra-row{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:11px 3px;border-bottom:1px solid var(--line)}
  .infra-row:last-child{border-bottom:none}
  .infra-row .n{font-weight:600} .infra-row .m{color:var(--dim);font-size:12px}
  .spark{display:flex;align-items:flex-end;gap:4px;height:78px;padding-top:6px}
  .bar{flex:1;background:var(--accent-dim);border-radius:3px 3px 0 0;position:relative;min-height:2px;transition:height .3s}
  .bar>span{position:absolute;inset:0 0 auto 0;background:linear-gradient(180deg,var(--accent),#c85e10);border-radius:3px 3px 0 0}
  .bar b{position:absolute;top:-17px;left:50%;transform:translateX(-50%);font-size:10px;color:var(--muted);opacity:0;transition:.15s;white-space:nowrap}
  .bar:hover b{opacity:1}
  .axis{display:flex;gap:4px;margin-top:6px}.axis span{flex:1;text-align:center;font-size:9.5px;color:var(--dim)}
  table{width:100%;border-collapse:collapse;font-size:13px}
  td{padding:8px 4px;border-bottom:1px solid var(--line)} tr:last-child td{border-bottom:none}
  td.r{text-align:right;color:var(--muted);font-variant-numeric:tabular-nums}
  .u{font-weight:600} .rank{color:var(--dim);width:22px}
  .tag{font-size:11px;color:var(--muted);background:var(--surface2);padding:2px 7px;border-radius:6px}
  .soon{border-style:dashed;opacity:.85}
  .soon .val{color:var(--dim)}
  .banner{display:flex;gap:10px;align-items:center;background:var(--accent-dim);border:1px solid #4a3016;border-radius:11px;padding:11px 14px;color:#ffcf9e;font-size:13px;margin-bottom:11px}
  .err{background:var(--bad-dim);border:1px solid #4a1c1a;color:#ff9b95;padding:10px 14px;border-radius:10px;margin:10px 0;font-size:13px;display:none}
  footer{color:var(--dim);font-size:11.5px;text-align:center;margin-top:34px}
</style></head>
<body><div class="wrap">
  <header>
    <div class="logo">🛣️</div>
    <div><h1>CruiseConnect · Monitoring</h1><div class="sub">Live-Übersicht · Nutzung · Routing · Infrastruktur</div></div>
    <div class="live"><span id="stamp">lädt…</span><span id="fresh"></span><span class="dot" id="livedot"></span><span>LIVE</span></div>
  </header>
  <div class="err" id="err"></div>

  <h2>Überblick</h2>
  <div class="grid g4" id="overview"></div>

  <h2>Fahrten — letzte 14 Tage</h2>
  <div class="card"><div class="spark" id="spark"></div><div class="axis" id="axis"></div></div>

  <h2>Routing &amp; Infrastruktur</h2>
  <div class="grid g2">
    <div class="grid g2" id="routing" style="align-content:start"></div>
    <div class="card"><div class="kpi"><div class="label">GraphHopper-Server</div></div><div id="infra" style="margin-top:6px"></div></div>
  </div>

  <h2>Community</h2>
  <div class="grid g4" id="community"></div>

  <h2>Werbung &amp; Abo</h2>
  <div id="monetslot"></div>

  <h2>Aktivität</h2>
  <div class="grid g2">
    <div class="card"><div class="kpi"><div class="label">Letzte Fahrten</div></div><table id="recent"></table></div>
    <div class="card"><div class="kpi"><div class="label">Top-Fahrer (km gesamt)</div></div><table id="topkm"></table></div>
  </div>

  <footer id="foot"></footer>
</div>
<script>
  var TOKEN = new URLSearchParams(location.search).get('token') || '';
  function el(html){var d=document.createElement('div');d.innerHTML=html;return d.firstChild;}
  function num(n){ if(n===null||n===undefined) return '–'; return Number(n).toLocaleString('de-DE'); }
  function kpi(label,val,unit,foot){
    return '<div class="card kpi"><div class="label">'+label+'</div><div class="val">'+val+(unit?'<small>'+unit+'</small>':'')+'</div>'+(foot?'<div class="foot">'+foot+'</div>':'')+'</div>';
  }
  function set(id,h){document.getElementById(id).innerHTML=h;}

  function render(d){
    var m=d.metrics||{}, inf=d.infra||{};
    var u=m.users||{},a=m.activity||{},r=m.rides||{},ro=m.routing||{},s=m.social||{},mo=m.monetization||{},md=m.moderation||{};

    set('overview',
      kpi('Nutzer gesamt', num(u.total), '', '<span class="up">+'+num(u.new_7d)+'</span> in 7 Tagen')+
      kpi('Aktiv (DAU / WAU / MAU)', num(a.dau)+' <small>/</small> '+num(a.wau)+' <small>/</small> '+num(a.mau), '', 'eindeutige Fahrer')+
      kpi('Fahrten gesamt', num(r.total), '', num(r.today)+' heute · '+num(r.d7)+' in 7 T.')+
      kpi('Distanz gesamt', num(r.km_total), 'km', num(r.km_7d)+' km in 7 T. · ⌀ '+num(r.avg_min)+' min')
    );

    // Sparkline
    var days=m.rides_14d||[]; var max=1; days.forEach(function(x){if(x.count>max)max=x.count;});
    set('spark', days.map(function(x){var h=Math.round(x.count/max*100);return '<div class="bar" title="'+x.day+'"><span style="height:'+h+'%"></span><b>'+x.count+' · '+x.km+'km</b></div>';}).join(''));
    set('axis', days.map(function(x,i){return '<span>'+(i%2===0?x.day:'')+'</span>';}).join(''));

    set('routing',
      kpi('Routen-Pool', num(ro.pool_size), '', num(ro.pool_cities)+' Städte · ⌀ Q '+num(ro.avg_quality))+
      kpi('Generierungen 24h', num(ro.gen_24h), '', num(ro.gen_7d)+' in 7 Tagen')
    );

    // Infra
    function irow(name,label,p){
      var up=p&&p.up; var cls=up?'ok':'bad'; var txt=up?('OK · '+(p.ms!=null?p.ms+' ms':'')):'OFFLINE';
      return '<div class="infra-row"><div><div class="n">'+name+'</div><div class="m">'+label+'</div></div><span class="pill '+cls+'">'+(up?'●':'○')+' '+txt+'</span></div>';
    }
    set('infra', irow('PC2 · vucko2','Primär (car + 4 Profile)',inf.pc2)+irow('PC1 · vucko','Fallback (Vollgraph)',inf.pc1));

    set('community',
      kpi('Posts', num(s.posts_total), '', num(s.posts_24h)+' in 24h')+
      kpi('Gruppen', num(s.groups_total), '', num(s.groups_7d)+' neu in 7 T.')+
      kpi('Communities', num(s.communities), '', num(s.comm_msgs_24h)+' Nachr. 24h')+
      kpi('Push-Geräte aktiv', num(s.tokens_active), '', 'von '+num(s.tokens_total)+' · '+num(md.reports_open)+' Meldungen offen')
    );

    // Monetization
    if(mo.connected){
      set('monetslot','<div class="grid g4">'+
        kpi('MRR', num(mo.mrr_eur), '€', 'monatl. wiederkehrend')+
        kpi('Zahlende Abos', num(mo.subs_paying), '', 'von '+num(mo.subs_total)+' gesamt')+
        kpi('Ad-Umsatz 7 T.', num(mo.ad_rev_7d), '€', num(mo.ad_impr_7d)+' Impressions')+
        kpi('ARPU (7 T.)', (u.total?((Number(mo.ad_rev_7d)/u.total).toFixed(2)):'0'), '€', 'Umsatz / Nutzer')+
      '</div>');
    } else {
      set('monetslot',
        '<div class="banner">💡 <div>Werbung &amp; Abos sind <b>vorbereitet, aber noch nicht angebunden</b>. Sobald AdMob / RevenueCat (o.ä.) in die Tabellen <span class="tag">subscriptions</span> <span class="tag">ad_revenue_daily</span> schreibt, füllt sich dieses Fenster automatisch mit echten Zahlen.</div></div>'+
        '<div class="grid g4">'+
        '<div class="card kpi soon"><div class="label">MRR</div><div class="val">– €</div><div class="foot">wartet auf Abo-Anbindung</div></div>'+
        '<div class="card kpi soon"><div class="label">Zahlende Abos</div><div class="val">–</div><div class="foot">RevenueCat / Stripe / IAP</div></div>'+
        '<div class="card kpi soon"><div class="label">Ad-Umsatz 7 T.</div><div class="val">– €</div><div class="foot">AdMob-Anbindung</div></div>'+
        '<div class="card kpi soon"><div class="label">Impressions 7 T.</div><div class="val">–</div><div class="foot">AdMob-Anbindung</div></div>'+
        '</div>');
    }

    var rec=m.recent||[];
    set('recent', rec.length ? rec.map(function(x){return '<tr><td class="u">'+esc(x.username)+'</td><td><span class="tag">'+esc(x.style)+'</span></td><td class="r">'+x.km+' km</td><td class="r">'+ago(x.ago_min)+'</td></tr>';}).join('') : '<tr><td class="m">Keine Fahrten</td></tr>');
    var tk=m.top_km||[];
    set('topkm', tk.map(function(x,i){return '<tr><td class="rank">'+(i+1)+'</td><td class="u">'+esc(x.username)+'</td><td class="r">'+num(x.km)+' km</td></tr>';}).join(''));

    document.getElementById('stamp').textContent = new Date(m.generated_at||Date.now()).toLocaleTimeString('de-DE');
    document.getElementById('foot').textContent = 'Automatische Aktualisierung 2×/Tag (0 Uhr & 12 Uhr) · CruiseConnect Admin-Monitoring';
    var e=document.getElementById('err'); if(d.error){e.style.display='block';e.textContent='DB-Fehler: '+d.error;} else {e.style.display='none';}
  }
  function esc(s){return String(s==null?'':s).replace(/[&<>]/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;'}[c];});}
  function ago(min){ if(min==null)return''; if(min<60)return min+' min'; if(min<1440)return Math.round(min/60)+' h'; return Math.round(min/1440)+' T'; }

  // Loader (2026-07-21, Vuckos Vorgabe nach Incident): genau 2 Aktualisierungen
  // pro Tag — 0 Uhr und 12 Uhr (Europe/Vienna), mehr nicht. Kein Fokus-/
  // Sichtbarkeits-/Online-Auto-Refresh mehr (die haben früher bei vielen
  // offenen Tabs zusätzliche Polls ausgelöst). Serverseitig gilt dieselbe
  // Sperre ohnehin zusätzlich (Halbtags-Slot-Cache) — dieser Client-Teil
  // vermeidet nur unnötige Requests, ist aber nicht die eigentliche Bremse.
  var lastOk=0;
  function load(){
    document.getElementById('livedot').style.background='var(--warn)';
    fetch('?data=1&token='+encodeURIComponent(TOKEN)+'&_='+Date.now(),{cache:'no-store'})
      .then(function(r){if(!r.ok)throw new Error('HTTP '+r.status);return r.json();})
      .then(function(d){render(d);lastOk=Date.now();document.getElementById('livedot').style.background='var(--ok)';})
      .catch(function(e){var el=document.getElementById('err');el.style.display='block';el.textContent='Verbindungsfehler: '+(e&&e.message||e)+' — neuer Versuch in 15 s';document.getElementById('livedot').style.background='var(--bad)';setTimeout(load,15000);});
  }
  setInterval(function(){
    if(!lastOk)return;
    var s=Math.round((Date.now()-lastOk)/1000);
    var f=document.getElementById('fresh');
    if(f)f.textContent=s<8?'· live':'· vor '+(s<120?s+' s':Math.round(s/60)+' min');
    // Reiner Notfall-Reload falls die Seite mal >14h hängt (Gerät stand still
    // o.ä.) — normal wird der Cache-Wechsel längst über scheduleNext() abgeholt.
    if(s>50400)location.reload();
  },5000);
  function msUntilNextSlot(){
    var parts=new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Vienna',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(new Date());
    var get=function(t){return Number(parts.find(function(p){return p.type===t;}).value);};
    var secNow=get('hour')*3600+get('minute')*60+get('second');
    var boundary=secNow<12*3600?12*3600:24*3600;
    return (boundary-secNow)*1000;
  }
  function scheduleNext(){
    setTimeout(function(){load();scheduleNext();},msUntilNextSlot()+5000);
  }
  load(); scheduleNext();
</script></body></html>`;
