// Das Dashboard als eigenes Modul, damit index.ts lesbar bleibt.
//
// 2026-08-07 (vucko): Burger-Menue auf dem Handy, Zeitraum-Filter
// (7 Tage / 30 Tage / 3 Monate / 1 Jahr), Wochenvergleich, ansprechendere
// Optik — und eine echte Anmeldung.
//
// BEWUSSTE ENTSCHEIDUNGEN:
//
// * KEINE fremden Skripte. Die Anmeldung spricht den Supabase-Auth-Endpunkt
//   direkt per fetch an, statt supabase-js von einem CDN zu laden. Damit gibt
//   es keine dritte Partei, die Zugangsdaten sehen koennte, und die Seite
//   funktioniert auch, wenn ein CDN ausfaellt.
//
// * DAS ZUGANGSTOKEN LEBT NUR IM ARBEITSSPEICHER. Kein localStorage, kein
//   Cookie. Genau deshalb muss man sich bei jeder Sitzung neu anmelden —
//   Tab zu, Token weg. Das war vuckos ausdrueckliche Vorgabe.
//
// * ALLE ZEITRAEUME WERDEN IM BROWSER GERECHNET, aus dem einen Verlauf, den
//   die Funktion mitliefert. Das Umschalten zwischen 7 Tagen und einem Jahr
//   loest KEINE einzige weitere Anfrage aus.
//
// Die eingebettete Skriptsprache verzichtet bewusst auf Backticks und
// ${...}, weil die ganze Seite selbst in einem Template-Literal steckt.

export const SEITE = `<!doctype html>
<html lang="de"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="robots" content="noindex,nofollow">
<title>Cruise Connector — Monitoring</title>
<style>
  :root{
    --bg:#080a0f; --bg2:#0e1119; --karte:#141822; --karte2:#1a1f2b;
    --linie:#232936; --text:#eef1f6; --grau:#8b94a4; --rot:#FF4D24;
    --rot2:#FF8B67; --gruen:#2ecc71; --gelb:#f6c445;
  }
  *{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
  html,body{margin:0;padding:0;background:var(--bg);color:var(--text);
    font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
    -webkit-font-smoothing:antialiased}
  a{color:inherit}

  /* ── Anmeldung ─────────────────────────────────────────────────────── */
  #anmeldung{position:fixed;inset:0;display:grid;place-items:center;padding:24px;
    background:radial-gradient(1200px 700px at 50% -10%,rgba(255,77,36,.16),transparent 60%),var(--bg);z-index:50}
  .box{width:100%;max-width:390px;background:linear-gradient(180deg,var(--karte),#10141d);
    border:1px solid var(--linie);border-radius:22px;padding:32px 26px;
    box-shadow:0 30px 80px rgba(0,0,0,.6)}
  .marke{display:flex;align-items:center;gap:11px;margin-bottom:22px}
  .marke .cc{width:42px;height:42px;border-radius:12px;background:var(--rot);
    display:grid;place-items:center;font-weight:900;font-size:17px;color:#fff;
    box-shadow:0 8px 24px rgba(255,77,36,.4)}
  .marke b{font-size:16px;letter-spacing:.2px}
  .marke span{display:block;font-size:11.5px;color:var(--grau);font-weight:500;letter-spacing:1.2px}
  .box h1{font-size:21px;margin:0 0 6px;font-weight:800;letter-spacing:-.3px}
  .box p.hint{margin:0 0 22px;color:var(--grau);font-size:13.5px}
  label{display:block;font-size:12px;color:var(--grau);margin:0 0 6px;font-weight:600;letter-spacing:.3px}
  input{width:100%;padding:13px 14px;border-radius:12px;border:1px solid var(--linie);
    background:#0b0e15;color:var(--text);font-size:15px;outline:none;transition:border-color .15s}
  input:focus{border-color:var(--rot)}
  .feld{margin-bottom:15px}
  button.haupt{width:100%;padding:14px;border:0;border-radius:12px;background:var(--rot);
    color:#fff;font-size:15px;font-weight:700;cursor:pointer;transition:filter .15s}
  button.haupt:hover{filter:brightness(1.08)}
  button.haupt:disabled{opacity:.55;cursor:default}
  .fehler{margin-top:14px;padding:11px 13px;border-radius:10px;font-size:13px;
    background:rgba(255,77,36,.12);border:1px solid rgba(255,77,36,.35);color:var(--rot2);display:none}
  .fuss{margin-top:20px;font-size:11.5px;color:#5c6472;text-align:center;line-height:1.6}

  /* ── Geruest ───────────────────────────────────────────────────────── */
  #app{display:none;min-height:100vh}
  .kopf{position:sticky;top:0;z-index:30;display:flex;align-items:center;gap:12px;
    padding:12px 16px;background:rgba(8,10,15,.88);backdrop-filter:blur(14px);
    border-bottom:1px solid var(--linie)}
  .burger{width:42px;height:42px;border-radius:11px;border:1px solid var(--linie);
    background:var(--karte);display:grid;place-items:center;cursor:pointer;flex:0 0 auto}
  .burger span{display:block;width:17px;height:2px;background:var(--text);border-radius:2px;
    position:relative}
  .burger span::before,.burger span::after{content:"";position:absolute;left:0;width:17px;
    height:2px;background:var(--text);border-radius:2px}
  .burger span::before{top:-6px} .burger span::after{top:6px}
  .kopf h2{font-size:16px;margin:0;font-weight:750;flex:1;letter-spacing:-.2px}
  .stand{font-size:11px;color:var(--grau);text-align:right;line-height:1.35}
  .stand b{display:block;color:var(--text);font-size:12px;font-weight:650}

  nav{position:fixed;inset:0 auto 0 0;width:255px;background:var(--bg2);
    border-right:1px solid var(--linie);padding:18px 12px;z-index:40;
    transform:translateX(-100%);transition:transform .22s ease;overflow-y:auto}
  nav.offen{transform:none}
  nav .titel{font-size:11px;color:#5c6472;letter-spacing:1.3px;font-weight:700;
    padding:10px 12px 8px}
  nav a{display:flex;align-items:center;gap:11px;padding:11px 12px;border-radius:11px;
    color:var(--grau);text-decoration:none;font-size:14.5px;font-weight:600;margin-bottom:2px}
  nav a.aktiv{background:rgba(255,77,36,.13);color:var(--rot2)}
  nav a:hover{background:var(--karte)}
  nav .pkt{width:7px;height:7px;border-radius:50%;background:currentColor;opacity:.6;flex:0 0 auto}
  #schleier{position:fixed;inset:0;background:rgba(0,0,0,.55);z-index:35;display:none}
  #schleier.an{display:block}

  main{padding:16px 16px 60px}

  /* ── Filterleiste ──────────────────────────────────────────────────── */
  .filter{display:flex;gap:7px;overflow-x:auto;padding:2px 0 12px;scrollbar-width:none}
  .filter::-webkit-scrollbar{display:none}
  .chip{flex:0 0 auto;padding:8px 14px;border-radius:999px;border:1px solid var(--linie);
    background:var(--karte);color:var(--grau);font-size:13px;font-weight:650;cursor:pointer;
    white-space:nowrap;transition:.15s}
  .chip.aktiv{background:var(--rot);border-color:var(--rot);color:#fff}
  .woche{display:flex;align-items:center;gap:10px;margin:0 0 16px;
    background:var(--karte);border:1px solid var(--linie);border-radius:13px;padding:9px 11px}
  .woche button{width:34px;height:34px;border-radius:9px;border:1px solid var(--linie);
    background:var(--karte2);color:var(--text);font-size:16px;cursor:pointer;line-height:1}
  .woche button:disabled{opacity:.35;cursor:default}
  .woche .mitte{flex:1;text-align:center;font-size:13px;font-weight:650}
  .woche .mitte small{display:block;color:var(--grau);font-weight:500;font-size:11.5px}

  /* ── Karten ────────────────────────────────────────────────────────── */
  .raster{display:grid;gap:11px;grid-template-columns:repeat(2,1fr);margin-bottom:16px}
  .k{background:linear-gradient(180deg,var(--karte),#11151e);border:1px solid var(--linie);
    border-radius:15px;padding:14px}
  .k .lbl{font-size:11.5px;color:var(--grau);font-weight:600;letter-spacing:.2px;
    margin-bottom:5px;display:flex;align-items:center;gap:5px}
  .k .wert{font-size:25px;font-weight:800;letter-spacing:-.7px;line-height:1.15}
  .k .delta{font-size:11.5px;font-weight:650;margin-top:4px}
  .hoch{color:var(--gruen)} .runter{color:var(--rot2)} .gleich{color:var(--grau)}
  .voll{grid-column:1/-1}
  h3.ab{font-size:12px;color:#5c6472;letter-spacing:1.2px;font-weight:700;
    margin:22px 0 10px;text-transform:uppercase}
  .liste{background:var(--karte);border:1px solid var(--linie);border-radius:15px;overflow:hidden}
  .zeile{display:flex;align-items:center;gap:10px;padding:12px 14px;border-bottom:1px solid var(--linie);font-size:14px}
  .zeile:last-child{border-bottom:0}
  .zeile .re{margin-left:auto;color:var(--grau);font-size:13px}
  .ampel{width:9px;height:9px;border-radius:50%;flex:0 0 auto}
  .hinweis{background:rgba(246,196,69,.09);border:1px solid rgba(246,196,69,.3);
    color:#e8c877;border-radius:12px;padding:11px 13px;font-size:12.5px;margin-bottom:14px}
  svg.chart{width:100%;height:150px;display:block}
  .legende{display:flex;gap:14px;font-size:11.5px;color:var(--grau);padding:8px 14px 12px}
  .legende i{display:inline-block;width:9px;height:3px;border-radius:2px;margin-right:5px;vertical-align:middle}

  @media(min-width:900px){
    nav{transform:none} #schleier{display:none!important}
    .burger{display:none}
    .kopf,main{margin-left:255px}
    main{padding:22px 28px 60px;max-width:1180px}
    .raster{grid-template-columns:repeat(4,1fr);gap:13px}
    .k .wert{font-size:28px}
  }
</style></head><body>

<div id="anmeldung">
  <form class="box" id="formular" autocomplete="on">
    <div class="marke">
      <div class="cc">CC</div>
      <div><b>Cruise Connector</b><span>MONITORING</span></div>
    </div>
    <h1>Anmelden</h1>
    <p class="hint">Nur f&uuml;r freigeschaltete Konten. Melde dich mit deinen normalen Cruise-Connector-Zugangsdaten an.</p>
    <div class="feld">
      <label for="email">E-Mail</label>
      <input id="email" type="email" autocomplete="username" required>
    </div>
    <div class="feld">
      <label for="pw">Passwort</label>
      <input id="pw" type="password" autocomplete="current-password" required>
    </div>
    <button class="haupt" id="knopf" type="submit">Anmelden</button>
    <div class="fehler" id="fehler"></div>
    <div class="fuss">Die Sitzung endet, sobald du den Tab schlie&szlig;t.<br>Jeder Versuch wird protokolliert.</div>
  </form>
</div>

<div id="app">
  <div id="schleier"></div>
  <nav id="nav">
    <div class="marke" style="padding:6px 12px 14px">
      <div class="cc">CC</div>
      <div><b>Monitoring</b><span id="wer">&nbsp;</span></div>
    </div>
    <div class="titel">BEREICHE</div>
    <a href="#/ueberblick" class="aktiv"><i class="pkt"></i>&Uuml;berblick</a>
    <a href="#/nutzer"><i class="pkt"></i>Nutzer</a>
    <a href="#/fahrten"><i class="pkt"></i>Fahrten</a>
    <a href="#/community"><i class="pkt"></i>Community</a>
    <a href="#/routing"><i class="pkt"></i>Routing</a>
    <a href="#/infra"><i class="pkt"></i>Infrastruktur</a>
    <a href="#/zugriffe"><i class="pkt"></i>Zugriffe</a>
    <div class="titel" style="margin-top:14px">SITZUNG</div>
    <a href="#" id="abmelden"><i class="pkt"></i>Abmelden</a>
  </nav>

  <div class="kopf">
    <div class="burger" id="burger"><span></span></div>
    <h2 id="seitentitel">&Uuml;berblick</h2>
    <div class="stand"><b id="standwert">&mdash;</b><span id="standtext">&nbsp;</span></div>
  </div>

  <main>
    <div class="filter" id="filter">
      <div class="chip aktiv" data-t="7">7 Tage</div>
      <div class="chip" data-t="30">30 Tage</div>
      <div class="chip" data-t="90">3 Monate</div>
      <div class="chip" data-t="365">1 Jahr</div>
      <div class="chip" data-t="woche">Woche vergleichen</div>
    </div>
    <div id="wochenleiste" style="display:none">
      <div class="woche">
        <button id="wZurueck">&#8249;</button>
        <div class="mitte"><span id="wTitel">Diese Woche</span><small id="wZeitraum">&nbsp;</small></div>
        <button id="wVor">&#8250;</button>
      </div>
    </div>
    <div id="inhalt"></div>
  </main>
</div>

<script>
(function(){
  var URL_BASIS = "__SUPABASE_URL__";
  var ANON = "__ANON_KEY__";
  var TOKEN = null;      // lebt NUR hier. Kein localStorage, kein Cookie.
  var DATEN = null;
  var ZEITRAUM = 7;
  var WOCHE_OFFSET = 0;  // 0 = diese Woche, 1 = vorige, ...

  var $ = function(id){ return document.getElementById(id); };
  var nf = new Intl.NumberFormat("de-AT");
  function z(n){ return (n===null||n===undefined||isNaN(n)) ? "\\u2014" : nf.format(Math.round(n)); }
  function z1(n){ return (n===null||n===undefined||isNaN(n)) ? "\\u2014" : nf.format(Math.round(n*10)/10); }
  function esc(s){ var d=document.createElement("div"); d.textContent=String(s==null?"":s); return d.innerHTML; }

  // ── Anmeldung ────────────────────────────────────────────────────────
  $("formular").addEventListener("submit", function(e){
    e.preventDefault();
    var k=$("knopf"), f=$("fehler");
    k.disabled=true; k.textContent="Anmelden \\u2026"; f.style.display="none";
    fetch(URL_BASIS+"/auth/v1/token?grant_type=password",{
      method:"POST",
      headers:{"content-type":"application/json","apikey":ANON},
      body:JSON.stringify({email:$("email").value.trim(),password:$("pw").value})
    }).then(function(r){ return r.json(); }).then(function(j){
      if(!j.access_token){ throw new Error(j.error_description||j.msg||"Anmeldung fehlgeschlagen."); }
      TOKEN=j.access_token;
      $("pw").value="";
      return laden();
    }).then(function(){
      $("anmeldung").style.display="none";
      $("app").style.display="block";
    }).catch(function(err){
      f.textContent=err.message||"Anmeldung fehlgeschlagen.";
      f.style.display="block";
    }).then(function(){
      k.disabled=false; k.textContent="Anmelden";
    });
  });

  $("abmelden").addEventListener("click", function(e){
    e.preventDefault(); TOKEN=null; DATEN=null;
    $("app").style.display="none"; $("anmeldung").style.display="grid";
  });

  function laden(){
    return fetch(location.pathname,{
      method:"POST",
      headers:{"authorization":"Bearer "+TOKEN,"content-type":"application/json"},
      body:"{}"
    }).then(function(r){
      return r.json().then(function(j){
        if(!r.ok) throw new Error(j.error||("Fehler "+r.status));
        return j;
      });
    }).then(function(j){
      DATEN=j;
      $("wer").textContent=j.angemeldet_als||"";
      if(j.stand){
        var d=new Date(j.stand);
        $("standwert").textContent=d.toLocaleDateString("de-AT",{day:"2-digit",month:"2-digit"})+" "+d.toLocaleTimeString("de-AT",{hour:"2-digit",minute:"2-digit"});
        $("standtext").textContent="letzter Stand";
      }
      zeichne();
    });
  }

  // ── Menue ────────────────────────────────────────────────────────────
  function menueZu(){ $("nav").classList.remove("offen"); $("schleier").classList.remove("an"); }
  $("burger").addEventListener("click", function(){
    $("nav").classList.toggle("offen"); $("schleier").classList.toggle("an");
  });
  $("schleier").addEventListener("click", menueZu);

  var SEITEN = {
    "#/ueberblick":"\\u00dcberblick", "#/nutzer":"Nutzer", "#/fahrten":"Fahrten",
    "#/community":"Community", "#/routing":"Routing", "#/infra":"Infrastruktur",
    "#/zugriffe":"Zugriffe"
  };
  window.addEventListener("hashchange", function(){ menueZu(); zeichne(); });

  // ── Filter ───────────────────────────────────────────────────────────
  Array.prototype.forEach.call(document.querySelectorAll("#filter .chip"), function(c){
    c.addEventListener("click", function(){
      Array.prototype.forEach.call(document.querySelectorAll("#filter .chip"), function(x){ x.classList.remove("aktiv"); });
      c.classList.add("aktiv");
      var t=c.getAttribute("data-t");
      if(t==="woche"){ ZEITRAUM="woche"; $("wochenleiste").style.display="block"; }
      else { ZEITRAUM=parseInt(t,10); $("wochenleiste").style.display="none"; }
      zeichne();
    });
  });
  $("wZurueck").addEventListener("click", function(){ WOCHE_OFFSET++; zeichne(); });
  $("wVor").addEventListener("click", function(){ if(WOCHE_OFFSET>0){ WOCHE_OFFSET--; zeichne(); } });

  // ── Verlauf auswerten ────────────────────────────────────────────────
  // Der Verlauf kommt absteigend (neu -> alt). Fuer einen Zeitraum suchen wir
  // den juengsten Punkt und den ersten, der mindestens so alt ist.
  function punktBei(tageZurueck){
    if(!DATEN||!DATEN.verlauf||!DATEN.verlauf.length) return null;
    var ziel=Date.now()-tageZurueck*86400000, best=null;
    for(var i=0;i<DATEN.verlauf.length;i++){
      var t=new Date(DATEN.verlauf[i].t).getTime();
      if(t<=ziel){ best=DATEN.verlauf[i]; break; }
    }
    return best||DATEN.verlauf[DATEN.verlauf.length-1];
  }
  function wert(punkt,pfad){
    if(!punkt||!punkt.m) return null;
    var o=punkt.m, teile=pfad.split(".");
    for(var i=0;i<teile.length;i++){ if(o==null) return null; o=o[teile[i]]; }
    return (typeof o==="number")?o:null;
  }
  function spanne(){
    if(ZEITRAUM==="woche"){
      return {von:(WOCHE_OFFSET+1)*7, bis:WOCHE_OFFSET*7,
              titel:WOCHE_OFFSET===0?"Diese Woche":(WOCHE_OFFSET===1?"Vorige Woche":"Vor "+WOCHE_OFFSET+" Wochen")};
    }
    return {von:ZEITRAUM, bis:0, titel:"Letzte "+ZEITRAUM+" Tage"};
  }
  /** Zuwachs eines kumulierten Zaehlers im gewaehlten Zeitraum. */
  function zuwachs(pfad){
    var s=spanne();
    var a=wert(punktBei(s.von),pfad), b=wert(punktBei(s.bis),pfad);
    if(a===null||b===null) return null;
    return b-a;
  }
  /** Derselbe Zuwachs in der davorliegenden, gleich langen Periode. */
  function zuwachsDavor(pfad){
    var s=spanne(), laenge=s.von-s.bis;
    var a=wert(punktBei(s.von+laenge),pfad), b=wert(punktBei(s.von),pfad);
    if(a===null||b===null) return null;
    return b-a;
  }
  function deltaHtml(pfad){
    var jetzt=zuwachs(pfad), davor=zuwachsDavor(pfad);
    if(jetzt===null) return "";
    if(davor===null||davor===0){
      return "<div class=\\"delta gleich\\">+"+z(jetzt)+" im Zeitraum</div>";
    }
    var p=((jetzt-davor)/Math.abs(davor))*100;
    var kl=p>1?"hoch":(p<-1?"runter":"gleich");
    var pf=p>0?"\\u2191 +":(p<0?"\\u2193 ":"\\u2192 ");
    return "<div class=\\"delta "+kl+"\\">+"+z(jetzt)+" \\u00b7 "+pf+z1(Math.abs(p))+"% ggü. davor</div>";
  }
  function karte(lbl,wert,extra){
    return "<div class=\\"k\\"><div class=\\"lbl\\">"+esc(lbl)+"</div><div class=\\"wert\\">"+wert+"</div>"+(extra||"")+"</div>";
  }

  function abdeckungshinweis(){
    if(!DATEN||!DATEN.abdeckung||!DATEN.abdeckung.aeltester) return "";
    var tage=Math.round((Date.now()-new Date(DATEN.abdeckung.aeltester).getTime())/86400000);
    var noetig = (ZEITRAUM==="woche") ? (WOCHE_OFFSET+1)*7 : ZEITRAUM;
    if(tage>=noetig) return "";
    return "<div class=\\"hinweis\\">Der Verlauf reicht bisher "+tage+" Tage zur&uuml;ck ("+DATEN.abdeckung.punkte+" Messpunkte). F&uuml;r diesen Zeitraum fehlen noch Daten \\u2014 er f&uuml;llt sich mit jedem Tag.</div>";
  }

  // ── Diagramm ─────────────────────────────────────────────────────────
  function chart(reihen){
    var alle=[]; reihen.forEach(function(r){ r.werte.forEach(function(v){ if(v!=null) alle.push(v); }); });
    if(!alle.length) return "<div style=\\"padding:22px;color:var(--grau);font-size:13px\\">Noch keine Verlaufsdaten.</div>";
    var max=Math.max.apply(null,alle), min=Math.min.apply(null,alle);
    if(max===min){ max=min+1; }
    var W=600,H=150,pad=8;
    var s="<svg class=\\"chart\\" viewBox=\\"0 0 "+W+" "+H+"\\" preserveAspectRatio=\\"none\\">";
    reihen.forEach(function(r){
      var n=r.werte.length; if(n<2) return;
      var d="";
      for(var i=0;i<n;i++){
        var v=r.werte[i]; if(v==null) continue;
        var x=pad+(i/(n-1))*(W-pad*2);
        var y=H-pad-((v-min)/(max-min))*(H-pad*2);
        d+=(d?" L":"M")+x.toFixed(1)+" "+y.toFixed(1);
      }
      s+="<path d=\\""+d+"\\" fill=\\"none\\" stroke=\\""+r.farbe+"\\" stroke-width=\\"2.5\\" stroke-linejoin=\\"round\\" stroke-linecap=\\"round\\"/>";
    });
    return s+"</svg>";
  }
  function verlaufsReihe(pfad,tage){
    if(!DATEN||!DATEN.verlauf) return [];
    var grenze=Date.now()-tage*86400000, out=[];
    for(var i=DATEN.verlauf.length-1;i>=0;i--){
      var p=DATEN.verlauf[i];
      if(new Date(p.t).getTime()<grenze) continue;
      out.push(wert(p,pfad));
    }
    return out;
  }

  // ── Seiten ───────────────────────────────────────────────────────────
  function zeichne(){
    if(!DATEN) return;
    var hash=location.hash||"#/ueberblick";
    if(!SEITEN[hash]){ hash="#/ueberblick"; }
    $("seitentitel").innerHTML=SEITEN[hash];
    Array.prototype.forEach.call(document.querySelectorAll("nav a"), function(a){
      a.classList.toggle("aktiv", a.getAttribute("href")===hash);
    });
    var s=spanne();
    $("wTitel").textContent=s.titel;
    $("wVor").disabled = WOCHE_OFFSET===0;
    if(ZEITRAUM==="woche"){
      var bisD=new Date(Date.now()-s.bis*86400000), vonD=new Date(Date.now()-s.von*86400000);
      $("wZeitraum").textContent=vonD.toLocaleDateString("de-AT")+" \\u2013 "+bisD.toLocaleDateString("de-AT");
    }
    if(DATEN.error){
      $("inhalt").innerHTML="<div class=\\"hinweis\\">"+esc(DATEN.error)+"</div>";
      return;
    }
    var m=DATEN.metrics||{}, tage=(ZEITRAUM==="woche")?(WOCHE_OFFSET+1)*7:ZEITRAUM;
    var h=abdeckungshinweis();

    if(hash==="#/ueberblick"){
      h+="<div class=\\"raster\\">"
        +karte("Nutzer gesamt", z((m.users||{}).total), deltaHtml("users.total"))
        +karte("Fahrten gesamt", z((m.rides||{}).total), deltaHtml("rides.total"))
        +karte("Kilometer gesamt", z((m.rides||{}).km_total), deltaHtml("rides.km_total"))
        +karte("Aktiv heute (DAU)", z((m.activity||{}).dau))
        +"</div>";
      h+="<h3 class=\\"ab\\">Verlauf</h3><div class=\\"liste\\">"
        +chart([{werte:verlaufsReihe("rides.total",tage),farbe:"#FF4D24"},
                {werte:verlaufsReihe("users.total",tage),farbe:"#2F80ED"}])
        +"<div class=\\"legende\\"><span><i style=\\"background:#FF4D24\\"></i>Fahrten</span><span><i style=\\"background:#2F80ED\\"></i>Nutzer</span></div></div>";
      h+="<h3 class=\\"ab\\">Infrastruktur</h3>"+infraListe();
    }
    else if(hash==="#/nutzer"){
      var u=m.users||{}, a=m.activity||{}, pl=m.platforms||{};
      h+="<div class=\\"raster\\">"
        +karte("Gesamt", z(u.total), deltaHtml("users.total"))
        +karte("Onboarding fertig", z(u.onboarded))
        +karte("DAU / WAU / MAU", z(a.dau)+" / "+z(a.wau)+" / "+z(a.mau))
        +karte("\\u00d8 Level", z1(u.avg_level))
        +karte("iOS", z(pl.ios))
        +karte("Android", z(pl.android))
        +karte("Neu (24 h)", z(u.new_24h))
        +karte("Gesperrt", z(u.banned))
        +"</div>";
      h+="<h3 class=\\"ab\\">Nutzerwachstum</h3><div class=\\"liste\\">"
        +chart([{werte:verlaufsReihe("users.total",tage),farbe:"#2F80ED"}])+"</div>";
    }
    else if(hash==="#/fahrten"){
      var r=m.rides||{};
      h+="<div class=\\"raster\\">"
        +karte("Fahrten gesamt", z(r.total), deltaHtml("rides.total"))
        +karte("Kilometer gesamt", z(r.km_total), deltaHtml("rides.km_total"))
        +karte("\\u00d8 Dauer", z(r.avg_min)+" min")
        +karte("Top-Speed", z1(r.top_speed_max)+" km/h")
        +karte("Heute", z(r.today))
        +karte("Letzte 7 Tage", z(r.d7))
        +karte("km (7 Tage)", z(r.km_7d))
        +karte("Mit Foto", z(r.photos))
        +"</div>";
      h+="<h3 class=\\"ab\\">Fahrten im Verlauf</h3><div class=\\"liste\\">"
        +chart([{werte:verlaufsReihe("rides.total",tage),farbe:"#FF4D24"}])+"</div>";
      if(m.recent&&m.recent.length){
        h+="<h3 class=\\"ab\\">Zuletzt gefahren</h3><div class=\\"liste\\">";
        m.recent.slice(0,8).forEach(function(x){
          h+="<div class=\\"zeile\\"><span>"+esc(x.username||"?")+"</span><span class=\\"re\\">"+z1(x.km)+" km \\u00b7 vor "+z(x.ago_min)+" min</span></div>";
        });
        h+="</div>";
      }
    }
    else if(hash==="#/community"){
      var so=m.social||{};
      h+="<div class=\\"raster\\">"
        +karte("Posts", z(so.posts_total), deltaHtml("social.posts_total"))
        +karte("Kommentare (24 h)", z(so.comments_24h))
        +karte("Follows", z(so.follows), deltaHtml("social.follows"))
        +karte("Gruppen", z(so.groups_total))
        +karte("Communities", z(so.communities))
        +karte("Chat (24 h)", z(so.comm_msgs_24h))
        +karte("Push-Ger\\u00e4te", z(so.tokens_active))
        +karte("Offene Meldungen", z((m.moderation||{}).reports_open))
        +"</div>";
      h+="<h3 class=\\"ab\\">Posts im Verlauf</h3><div class=\\"liste\\">"
        +chart([{werte:verlaufsReihe("social.posts_total",tage),farbe:"#2ecc71"}])+"</div>";
    }
    else if(hash==="#/routing"){
      var ro=m.routing||{};
      h+="<div class=\\"raster\\">"
        +karte("Routen-Pool", z(ro.pool_size))
        +karte("Gepr\\u00fcft", z(ro.pool_verified))
        +karte("St\\u00e4dte", z(ro.pool_cities))
        +karte("\\u00d8 Qualit\\u00e4t", z1(ro.avg_quality))
        +karte("Generierungen (24 h)", z(ro.gen_24h))
        +karte("Generierungen (7 T)", z(ro.gen_7d))
        +"</div>";
      if(m.styles&&m.styles.length){
        h+="<h3 class=\\"ab\\">Fahrstile</h3><div class=\\"liste\\">";
        m.styles.forEach(function(x){
          h+="<div class=\\"zeile\\"><span>"+esc(x.style||x.k||"?")+"</span><span class=\\"re\\">"+z(x.c||x.count)+"</span></div>";
        });
        h+="</div>";
      }
    }
    else if(hash==="#/infra"){
      var st=m.stability||{};
      h+=infraListe();
      h+="<h3 class=\\"ab\\">Stabilit\\u00e4t</h3><div class=\\"raster\\">"
        +karte("Fehler (24 h)", z(st.errors_24h))
        +karte("Abst\\u00fcrze (24 h)", z(st.fatal_24h))
        +karte("Abst\\u00fcrze (7 T)", z(st.fatal_7d))
        +karte("Betroffene (7 T)", z(st.affected_7d))
        +"</div>";
    }
    else if(hash==="#/zugriffe"){
      h+="<div class=\\"hinweis\\">Dieses Dashboard ist nur f\\u00fcr freigeschaltete Konten erreichbar. Jeder Versuch wird protokolliert; unberechtigte l\\u00f6sen eine Push-Meldung aus.</div>";
      h+="<div class=\\"raster\\">"
        +karte("Angemeldet als", esc(DATEN.angemeldet_als||"\\u2014"))
        +karte("Messpunkte", z((DATEN.abdeckung||{}).punkte))
        +"</div>";
    }
    $("inhalt").innerHTML=h;
  }

  function infraListe(){
    var i=DATEN.infra||{}, out="<div class=\\"liste\\">";
    [["PC2 \\u00b7 vucko2",i.pc2],["PC1 \\u00b7 vucko",i.pc1]].forEach(function(p){
      var up=p[1]&&p[1].up;
      out+="<div class=\\"zeile\\"><i class=\\"ampel\\" style=\\"background:"+(up?"#2ecc71":"#FF4D24")+"\\"></i><span>"+p[0]+"</span><span class=\\"re\\">"+(up?(p[1].ms+" ms"):"nicht erreichbar")+"</span></div>";
    });
    return out+"</div>";
  }
})();
</script></body></html>`;
