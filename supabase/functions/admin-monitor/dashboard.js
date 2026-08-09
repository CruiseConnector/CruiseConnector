/* ───────────────────────────────────────────────────────────────────────────
   Monitoring-Dashboard, Logik.

   GRUNDSATZ: Ein einziger Serveraufruf je Sitzung. Danach wird ausschliesslich
   hier gerechnet. Ein Klick auf einen Filter, ein Bereichswechsel oder ein
   Wochensprung loest KEINE Abfrage aus. Die Datenbank wurde einmal ueberlastet,
   das darf nicht wieder passieren.

   DATEN, DIE DER SERVER SCHICKT:
     metrics    Momentaufnahme (users, rides, social, routing, geo, styles,
                top_km, recent, trend_14d ...)
     history    12 Wochen je Kennzahl, parallel zu history.labels
     today      24 Stunden (rides, posts, users_new, generations)
     compare    7 Tage gegen die 7 Tage davor
     analytics  Trichter, Heatmap (Wochentag x Stunde), Bindungs-Kohorten,
                Routing-Laufzeiten
     verlauf    alle Schnappschuesse, absteigend (t, slot, m)
     infra      Zustand und Verlauf der beiden Mini-PCs

   Bis heute las der Browser NUR metrics und verlauf. history, today, compare
   und analytics wurden mitgeschickt und weggeworfen.
   ─────────────────────────────────────────────────────────────────────────── */
(function () {
'use strict';

var API = '__API_URL__';

var TOKEN = null;
var NAME = '';
var DATEN = null;
var ZEITRAUM = 7;
var WOCHE_OFFSET = 0;
var BEREICH = 'ueberblick';
var GEWAEHLT = null;
var LAEUFT = false;

var F = { rot:'#FF4D24', rot2:'#FF8B67', blau:'#3B82F6', blau2:'#7DAEFF',
          gruen:'#2ecc71', gelb:'#f6c445', lila:'#A78BFA', tuerkis:'#22D3EE',
          grau:'#8b94a4' };

var TITEL = { ueberblick:'Überblick', heute:'Heute', leute:'Leute', nutzer:'Nutzer', fahrten:'Fahrten',
              community:'Community', routing:'Routing', infra:'Infrastruktur',
              zugriffe:'Zugriffe' };

/* ── Vergleichsmodus ──────────────────────────────────────────────────────
   2026-08-09 (vucko): „wenn man sieht, dass man sehr viele Nutzer in den
   letzten drei Tagen bekommen hat aber dadurch, dass er in den letzten sieben
   Tagen etwas anders ist da rot ... da moechte ich, dass man so ein Modus hat
   wirklich mit letzter Woche vergleichen und nicht mit letzter Woche
   vergleichen."

   Das Problem ist echt: Eine starke Woche NACH einer noch staerkeren sieht rot
   aus, obwohl gewachsen wurde. Rot heisst dann nicht „schlecht", sondern nur
   „weniger als davor" — und demotiviert grundlos.

   'vorwoche' = wie bisher, mit Pfeil und Prozent gegen den Zeitraum davor.
   'ohne'     = nur der reine Zuwachs, neutral eingefaerbt, kein Rot, kein
                Prozentwert. Die Zahl steht fuer sich.
   Die Wahl liegt im Browser (localStorage) und ueberlebt das Neuladen. */
var VERGLEICH = 'vorwoche';
try { VERGLEICH = localStorage.getItem('cc_vergleich') || 'vorwoche'; } catch(e){}
function vergleichAn(){ return VERGLEICH === 'vorwoche'; }
function setzeVergleich(v){
  VERGLEICH = v;
  try { localStorage.setItem('cc_vergleich', v); } catch(e){}
  zeichne();
}

/* ══ Helfer ═══════════════════════════════════════════════════════════════ */
function $(id){ return document.getElementById(id); }
function el(sel,wurzel){ return (wurzel||document).querySelector(sel); }
function alle(sel,wurzel){ return Array.prototype.slice.call((wurzel||document).querySelectorAll(sel)); }

var nfGanz = new Intl.NumberFormat('de-DE');
var nfEins = new Intl.NumberFormat('de-DE',{minimumFractionDigits:1,maximumFractionDigits:1});

function z(n){ return (n===null||n===undefined||isNaN(n)) ? '–' : nfGanz.format(Math.round(n)); }
function z1(n){ return (n===null||n===undefined||isNaN(n)) ? '–' : nfEins.format(n); }
function esc(s){
  return String(s===null||s===undefined?'':s)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
/** Kurz fuer Achsen: 1200 wird 1,2k. */
function kurz(n){
  if(n===null||n===undefined||isNaN(n)) return '';
  var a=Math.abs(n);
  if(a>=1000000) return nfEins.format(n/1000000)+'M';
  if(a>=1000)    return nfEins.format(n/1000)+'k';
  return nfGanz.format(Math.round(n*10)/10);
}

var wochentage = ['So','Mo','Di','Mi','Do','Fr','Sa'];

/** trend_14d liefert den Tag als "07-25", also ohne Jahr. Ein blosses
 *  new Date("07-25") ergibt je nach Browser Unsinn oder gar nichts. Deshalb
 *  wird das Jahr hier ergaenzt: liegt der Monat in der Zukunft, war es das
 *  Vorjahr (greift jedes Mal um den Jahreswechsel). */
function alsDatum(v){
  if(v===null||v===undefined) return null;
  var s=String(v);
  var kurzTag=s.match(/^(\d{2})-(\d{2})$/);
  if(kurzTag){
    var heute=new Date();
    var monat=parseInt(kurzTag[1],10)-1, tag=parseInt(kurzTag[2],10);
    var jahr=heute.getFullYear();
    if(monat>heute.getMonth()+1) jahr--;
    var k=new Date(jahr,monat,tag);
    return isNaN(k.getTime())?null:k;
  }
  var d=new Date(v);
  return isNaN(d.getTime())?null:d;
}
/** „Mi, 06.08." — nie „undefined", auch wenn nichts hereinkommt. */
function tagKurz(v){
  if(v===null||v===undefined||v==='') return '–';
  var d=alsDatum(v); if(!d) return String(v);
  return wochentage[d.getDay()]+', '+String(d.getDate()).padStart(2,'0')+'.'+String(d.getMonth()+1).padStart(2,'0')+'.';
}
/** „Mi, 06.08.2026 um 12:10" */
function tagLang(v){
  if(v===null||v===undefined||v==='') return '–';
  var d=alsDatum(v); if(!d) return String(v);
  return tagKurz(v)+d.getFullYear()+' um '+
         String(d.getHours()).padStart(2,'0')+':'+String(d.getMinutes()).padStart(2,'0');
}
function vorWie(v){
  var d=alsDatum(v); if(!d) return '';
  var s=Math.max(0,(Date.now()-d.getTime())/1000);
  if(s<90) return 'gerade eben';
  if(s<5400) return 'vor '+Math.round(s/60)+' Minuten';
  if(s<172800) return 'vor '+Math.round(s/3600)+' Stunden';
  return 'vor '+Math.round(s/86400)+' Tagen';
}
/** Faellt der Zeitpunkt auf den heutigen Kalendertag? */
function istHeute(v){
  var d=alsDatum(v); if(!d) return false;
  var n=new Date();
  return d.getFullYear()===n.getFullYear() && d.getMonth()===n.getMonth() && d.getDate()===n.getDate();
}
/** „06:10" */
function uhrzeit(v){
  var d=alsDatum(v); if(!d) return '';
  return String(d.getHours()).padStart(2,'0')+':'+String(d.getMinutes()).padStart(2,'0');
}
function dauerSeit(v){
  var d=alsDatum(v); if(!d) return '–';
  var s=Math.max(0,(Date.now()-d.getTime())/1000);
  if(s<5400) return Math.round(s/60)+' Min';
  if(s<172800) return Math.round(s/3600)+' Std';
  return Math.round(s/86400)+' Tagen';
}

function melde(text, schlimm){
  var t=$('toast');
  t.textContent=text;
  t.className='toast an'+(schlimm?' schlimm':'');
  clearTimeout(melde._u);
  melde._u=setTimeout(function(){ t.className='toast'+(schlimm?' schlimm':''); },3400);
}

/** Karten und Bloecke gestaffelt einblenden, statt alle gleichzeitig. */
function staffeln(wurzel){
  alle('.k, .block', wurzel).forEach(function(n,i){
    n.style.animationDelay = Math.min(i*38,420)+'ms';
  });
}

/* ══ Serveraufruf ═════════════════════════════════════════════════════════ */
function ruf(koerper){
  return fetch(API,{
    method:'POST',
    headers:{'content-type':'application/json'},
    body:JSON.stringify(koerper)
  }).then(function(r){
    return r.json().catch(function(){ return {error:'Antwort nicht lesbar.'}; })
      .then(function(j){ j.__status=r.status; return j; });
  });
}

/* ══ Anmeldung ════════════════════════════════════════════════════════════ */
alle('.wahlKnopf').forEach(function(b){
  b.addEventListener('click',function(){
    alle('.wahlKnopf').forEach(function(x){ x.classList.remove('aktiv'); });
    b.classList.add('aktiv');
    GEWAEHLT=b.getAttribute('data-benutzer');
    $('knopfAnmelden').disabled=false;
    $('pw').focus();
  });
});

$('formAnmeldung').addEventListener('submit',function(e){
  e.preventDefault();
  if(!GEWAEHLT){ $('fehlerAnmeldung').innerHTML='<div class="fehler">Bitte zuerst Vucko oder Luca ausw&auml;hlen.</div>'; return; }
  var knopf=$('knopfAnmelden');
  knopf.disabled=true; knopf.innerHTML='<span class="dreher"></span>';
  $('fehlerAnmeldung').innerHTML='';

  ruf({aktion:'login',benutzer:GEWAEHLT,passwort:$('pw').value}).then(function(a){
    knopf.disabled=false; knopf.textContent='Anmelden';
    if(a.error){ $('fehlerAnmeldung').innerHTML='<div class="fehler">'+esc(a.error)+'</div>'; return; }
    TOKEN=a.token; NAME=a.name||GEWAEHLT;
    if(a.passwort_aendern_noetig){ zeigeWechsel(); return; }
    starte();
  }).catch(function(){
    knopf.disabled=false; knopf.textContent='Anmelden';
    $('fehlerAnmeldung').innerHTML='<div class="fehler">Keine Verbindung zum Server.</div>';
  });
});

function zeigeWechsel(){
  $('anmeldung').style.display='none';
  $('wechsel').style.display='grid';
  $('wAlt').focus();
}

$('formWechsel').addEventListener('submit',function(e){
  e.preventDefault();
  var alt=$('wAlt').value, neu=$('wNeu').value, neu2=$('wNeu2').value;
  var box=$('fehlerWechsel'); box.innerHTML='';
  if(neu.length<10){ box.innerHTML='<div class="fehler">Mindestens 10 Zeichen.</div>'; return; }
  if(neu!==neu2){ box.innerHTML='<div class="fehler">Die beiden neuen Passw&ouml;rter stimmen nicht &uuml;berein.</div>'; return; }
  ruf({aktion:'passwort',token:TOKEN,alt:alt,neu:neu}).then(function(a){
    if(a.error){ box.innerHTML='<div class="fehler">'+esc(a.error)+'</div>'; return; }
    $('wechsel').style.display='none';
    melde('Passwort gespeichert.');
    starte();
  });
});

$('abmelden').addEventListener('click',function(e){
  e.preventDefault();
  if(TOKEN) ruf({aktion:'logout',token:TOKEN});
  TOKEN=null;
  location.reload();
});

/* ══ Daten holen ══════════════════════════════════════════════════════════ */
function starte(){
  $('anmeldung').style.display='none';
  $('wechsel').style.display='none';
  $('app').style.display='block';
  $('navName').textContent=NAME;
  $('inhalt').innerHTML='<div class="skelett"></div><div class="skelett" style="height:190px"></div><div class="skelett"></div>';

  ruf({aktion:'daten',token:TOKEN}).then(function(a){
    if(a.passwort_aendern_noetig){ $('app').style.display='none'; zeigeWechsel(); return; }
    if(a.error && !a.metrics){
      $('inhalt').innerHTML='<div class="hinweis schlimm">'+esc(a.error)+'</div>';
      return;
    }
    DATEN=a;
    kopfFuellen();
    neuigkeitPruefen();
    zeichne();
  }).catch(function(){
    $('inhalt').innerHTML='<div class="hinweis schlimm">Daten konnten nicht geladen werden.</div>';
  });
}

/** Holt den aktuellen Schnappschuss nach, ohne die Ansicht zu leeren.
 *  Faellt der Aufruf durch, bleibt schlicht der letzte bekannte Stand stehen —
 *  eine halb geleerte Seite waere schlechter als eine leicht veraltete. */
function nachladen(erzwungen){
  return ruf({aktion:'daten',token:TOKEN}).then(function(a){
    if(!a || a.error || !a.metrics) return false;
    // Nur neu zeichnen, wenn wirklich ein neuer Schnappschuss vorliegt —
    // sonst flackert eine offene Wand-Ansicht bei jedem 20-Minuten-Puls.
    var neuerStand = !DATEN || a.stand !== DATEN.stand;
    DATEN=a;
    $('standWert').textContent=tagLang(DATEN.stand);
    $('standAlter').textContent=vorWie(DATEN.stand);
    $('fussStand').textContent='Stand '+tagLang(DATEN.stand);
    var ab=DATEN.abdeckung||{};
    if($('fussPunkte')) $('fussPunkte').textContent=(ab.punkte||0)+' Schnappschüsse gespeichert';
    if(erzwungen || neuerStand) zeichne();
    return neuerStand;
  }).catch(function(){ return false; });
}

function kopfFuellen(){
  $('standWert').textContent=tagLang(DATEN.stand);
  $('standAlter').textContent=vorWie(DATEN.stand);
  $('fussStand').textContent='Stand '+tagLang(DATEN.stand);
  var ab=DATEN.abdeckung||{};
  $('fussPunkte').textContent=(ab.punkte||0)+' Schnappschüsse gespeichert';
  // Alle 30 Sekunden nur die Alterangabe auffrischen. Kein Serveraufruf.
  setInterval(function(){ $('standAlter').textContent=vorWie(DATEN.stand); },30000);

  // 2026-08-09 (vucko): „schau, dass sich das Monitoring-Tool alle 6 Stunden
  // selber updated." Die Seite holt sich den Schnappschuss also von allein,
  // ohne dass jemand F5 druecken muss.
  //
  // ZWEI Wecker, und beide sind billig: Der eine laeuft nach 6 Stunden ab. Der
  // andere prueft beim Zurueckkehren auf den Tab, ob der angezeigte Stand
  // aelter als 6 Stunden ist — ein Laptop im Ruhezustand haelt naemlich auch
  // jeden Timer an, und ohne diese zweite Pruefung stuende am Morgen die Zahl
  // vom Vorabend auf dem Schirm.
  //
  // Die Datenbank kostet das nichts: Es wird ein bereits berechneter
  // Schnappschuss gelesen, nicht neu gerechnet. Gerechnet wird nur viermal
  // taeglich im Cron.
  if(!window.__auffrischWecker){
    // Alle 20 Minuten den Server FRAGEN, ob ein neuer 6-Stunden-Schnappschuss
    // vorliegt. Das ist ein billiger, indizierter Lesezugriff — gerechnet wird
    // weiterhin nur viermal am Tag im Cron. Neu gezeichnet wird nur, wenn sich
    // der Stand tatsaechlich geaendert hat (nachladen() prueft das selbst).
    //
    // Warum 20 Minuten statt „genau nach 6 Stunden": Ein starr alle 6 Stunden
    // laufender Timer waere an die Ladezeit der Seite gekoppelt, nicht an die
    // 0/6/12/18-Uhr-Grenzen. Eine um 5 Uhr geoeffnete Wand-Ansicht wuerde den
    // 6-Uhr-Schnappschuss sonst erst um 11 Uhr sehen. Mit dem 20-Minuten-Puls
    // ist ein neuer Schnappschuss spaetestens 20 Minuten nach seiner Entstehung
    // auf dem Schirm — zuverlaessig, ohne dass jemand neu laden muss.
    window.__auffrischWecker = setInterval(function(){ nachladen(false); }, 20*60*1000);

    // Zusaetzlich beim Zurueckkehren auf den Tab sofort nachsehen — ein Laptop
    // im Ruhezustand haelt jeden Timer an, sonst stuende am Morgen die Zahl vom
    // Vorabend auf dem Schirm.
    document.addEventListener('visibilitychange', function(){
      if(document.visibilityState==='visible' && DATEN && DATEN.stand) nachladen(false);
    });
  }

  // „Jetzt aktualisieren"-Knopf im Kopf — einmalig verdrahten.
  if(!window.__jetztVerdrahtet){
    window.__jetztVerdrahtet = true;
    var jk=$('knopfJetzt');
    if(jk){
      jk.addEventListener('click', function(){
        if(jk.disabled) return;
        jk.disabled=true; jk.classList.add('dreht');
        ruf({aktion:'snapshot_jetzt',token:TOKEN}).then(function(a){
          if(a && a.ok){
            nachladen(true).then(function(){ melde('Zahlen frisch berechnet.'); });
          } else if(a && a.grund==='zu_frueh'){
            melde('Gerade eben schon aktualisiert. In '+(a.wartesekunden||60)+' Sekunden wieder möglich.');
          } else {
            melde('Aktualisierung nicht durchgekommen.',true);
          }
        }).catch(function(){
          melde('Aktualisierung fehlgeschlagen.',true);
        }).then(function(){
          jk.disabled=false; jk.classList.remove('dreht');
        });
      });
    }
  }

  var tot=(DATEN.infra&&DATEN.infra.hosts||[]).filter(function(h){ return h.up===false; });
  $('infraMarker').style.display = tot.length ? 'inline-block' : 'none';
}

/** Was hat sich seit dem letzten Besuch getan? Reine Browser-Sache. */
function neuigkeitPruefen(){
  try{
    var schluessel='cc_monitor_letzter_stand';
    var vorher=localStorage.getItem(schluessel);
    if(vorher && vorher!==DATEN.stand){
      var alt=(DATEN.verlauf||[]).filter(function(p){ return p.t===vorher; })[0];
      if(alt){
        var dn=(wertAus(DATEN.metrics,'users.total')||0)-(wertAus(alt.m,'users.total')||0);
        var df=(wertAus(DATEN.metrics,'rides.total')||0)-(wertAus(alt.m,'rides.total')||0);
        if(dn||df) DATEN.__neu={nutzer:dn,fahrten:df,seit:vorher};
      }
    }
    localStorage.setItem(schluessel,DATEN.stand);
  }catch(e){ /* privater Modus: dann eben ohne */ }
}

/* ══ Menue ════════════════════════════════════════════════════════════════ */
function menue(auf){
  $('nav').classList.toggle('offen',auf);
  $('schleier').classList.toggle('an',auf);
}
$('burger').addEventListener('click',function(){ menue(!$('nav').classList.contains('offen')); });
$('schleier').addEventListener('click',function(){ menue(false); });

window.addEventListener('hashchange',function(){
  var h=(location.hash||'#ueberblick').slice(1);
  if(TITEL[h]){ BEREICH=h; menue(false); zeichne(); }
});

document.addEventListener('keydown',function(e){
  if(e.target && /INPUT|TEXTAREA/.test(e.target.tagName)) return;
  if(e.key==='Escape'){ menue(false); return; }
  var reihen=['ueberblick','nutzer','fahrten','community','routing','infra','zugriffe'];
  var i=parseInt(e.key,10);
  if(i>=1 && i<=reihen.length){ location.hash='#'+reihen[i-1]; }
});

/* ══ Filter ═══════════════════════════════════════════════════════════════ */
alle('#filter .chip').forEach(function(c){
  c.addEventListener('click',function(){
    alle('#filter .chip').forEach(function(x){ x.classList.remove('aktiv'); });
    c.classList.add('aktiv');
    var t=c.getAttribute('data-t');
    if(t==='woche'){ ZEITRAUM='woche'; $('wochenleiste').style.display='block'; }
    else { ZEITRAUM=parseInt(t,10); $('wochenleiste').style.display='none'; }
    zeichne();
  });
});
$('wZurueck').addEventListener('click',function(){ WOCHE_OFFSET++; zeichne(); });
$('wVor').addEventListener('click',function(){ if(WOCHE_OFFSET>0){ WOCHE_OFFSET--; zeichne(); } });

/* ══ Verlaufsauswertung ═══════════════════════════════════════════════════ */
function wertAus(objekt,pfad){
  var t=String(pfad).split('.'), v=objekt;
  for(var i=0;i<t.length;i++){
    if(v===null||v===undefined) return null;
    v=v[t[i]];
  }
  return (typeof v==='number') ? v : null;
}
/** Aeltester Punkt, der noch mindestens so weit zurueckliegt. */
function punktBei(tageZurueck){
  var v=DATEN&&DATEN.verlauf;
  if(!v||!v.length) return null;
  var ziel=Date.now()-tageZurueck*86400000;
  for(var i=0;i<v.length;i++){
    if(new Date(v[i].t).getTime()<=ziel) return v[i];
  }
  return v[v.length-1];
}
function wert(punkt,pfad){ return punkt ? wertAus(punkt.m,pfad) : null; }

function spanne(){
  if(ZEITRAUM==='woche'){
    return { von:(WOCHE_OFFSET+1)*7, bis:WOCHE_OFFSET*7,
             titel: WOCHE_OFFSET===0?'Diese Woche':(WOCHE_OFFSET===1?'Vorige Woche':'Vor '+WOCHE_OFFSET+' Wochen') };
  }
  return { von:ZEITRAUM, bis:0, titel:ZEITRAUM+' Tage' };
}
function zuwachs(pfad){
  var s=spanne();
  var a=wert(punktBei(s.von),pfad), b=wert(punktBei(s.bis),pfad);
  return (a===null||b===null) ? null : b-a;
}
function zuwachsDavor(pfad){
  var s=spanne(), laenge=s.von-s.bis;
  var a=wert(punktBei(s.von+laenge),pfad), b=wert(punktBei(s.von),pfad);
  return (a===null||b===null) ? null : b-a;
}
function deltaHtml(pfad){
  var jetzt=zuwachs(pfad), davor=zuwachsDavor(pfad);
  if(jetzt===null) return '';
  // Ohne Vergleich: nur der Zuwachs, immer neutral. Kein Rot fuer eine Woche,
  // die schwaecher als die davor war, aber trotzdem Wachstum gebracht hat.
  if(!vergleichAn()) return '<div class="delta gleich">+'+z(jetzt)+' im Zeitraum</div>';
  if(davor===null||davor===0) return '<div class="delta gleich">+'+z(jetzt)+' im Zeitraum</div>';
  var p=((jetzt-davor)/Math.abs(davor))*100;
  var kl=p>1?'hoch':(p<-1?'runter':'gleich');
  var pf=p>0?'↑ +':(p<0?'↓ ':'→ ');
  // Kurz halten, sonst bricht die Zeile in der Kachel um und die Karten
  // sehen ungleich aus. Die volle Erklaerung steht im Titel zum Aufzeigen.
  return '<div class="delta '+kl+'" title="Zuwachs im gewählten Zeitraum, verglichen mit dem gleich langen Zeitraum davor">'+
         '+'+z(jetzt)+' · '+pf+z1(Math.abs(p))+'% davor</div>';
}

/** Reihe aus dem Schnappschuss-Verlauf, aufsteigend, mit Zeitstempeln.
 *  Das sind LAUFENDE SUMMEN. */
function verlaufsReihe(pfad,tage){
  var v=(DATEN&&DATEN.verlauf)||[];
  var grenze=Date.now()-tage*86400000;
  var werte=[], marken=[];
  for(var i=v.length-1;i>=0;i--){
    var t=new Date(v[i].t).getTime();
    if(t<grenze) continue;
    var w=wertAus(v[i].m,pfad);
    if(w===null) continue;
    werte.push(w); marken.push(v[i].t);
  }
  return { werte:werte, marken:marken };
}

/* ─────────────────────────────────────────────────────────────────────────
   ZUWACHS JE TAG.

   2026-08-07 (vucko): „aus dieser grafik sehe ich leider keine daten heraus
   die mir was bringen."

   Er hatte recht. Gezeigt wurde die laufende Gesamtsumme — die kann nur
   steigen. Man sieht daran, DASS es mehr wird, aber nie, wie viel an welchem
   Tag dazukam. Ein flacher Tag und ein starker Tag sehen fast gleich aus.

   Hier wird deshalb je Kalendertag der letzte Stand genommen und die
   Differenz zum Vortag gebildet. Das ergibt „an diesem Tag neu" und ist die
   Zahl, die tatsaechlich etwas aussagt.
   ───────────────────────────────────────────────────────────────────────── */
function tagesSchluessel(d){
  return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
}
function proTagReihe(pfad,tage){
  var v=(DATEN&&DATEN.verlauf)||[];
  // Einen Tag mehr holen, damit der erste angezeigte Tag einen Vorgaenger hat.
  var grenze=Date.now()-(tage+1.5)*86400000;
  var jeTag={}, folge=[];
  for(var i=v.length-1;i>=0;i--){
    var d=new Date(v[i].t);
    if(d.getTime()<grenze) continue;
    var w=wertAus(v[i].m,pfad);
    if(w===null) continue;
    var k=tagesSchluessel(d);
    if(jeTag[k]===undefined) folge.push({k:k,d:new Date(d.getFullYear(),d.getMonth(),d.getDate())});
    jeTag[k]=w;                    // aufsteigend gelesen, also bleibt der letzte Stand stehen
  }
  var werte=[], marken=[];
  for(var j=1;j<folge.length;j++){
    var zu=jeTag[folge[j].k]-jeTag[folge[j-1].k];
    werte.push(Math.max(0,zu));    // negative Spruenge sind Bereinigungen, keine Aussage
    marken.push(folge[j].d.toISOString());
  }
  // Der Vortag wurde nur geholt, um die erste Differenz bilden zu koennen.
  // Ohne diesen Schnitt liefert der 14-Tage-Filter 15 Balken — und riss damit
  // die Schwelle, ab der die Zahlen an den Balken angeschrieben werden.
  // Genau deshalb waren beim 14-Tage-Filter gar keine Zahlen mehr zu sehen.
  if(werte.length>tage){
    werte=werte.slice(werte.length-tage);
    marken=marken.slice(marken.length-tage);
  }
  // Bleibt nach dem Differenzieren nichts uebrig, lieber die Summe zeigen als
  // ein leeres Feld.
  if(!werte.length) return { werte:[], marken:[], leer:true };
  return { werte:werte, marken:marken };
}

function karte(lbl,wert,extra,funke){
  return '<div class="k"><div class="lbl">'+esc(lbl)+'</div><div class="wert">'+wert+'</div>'+
         (extra||'')+(funke||'')+'</div>';
}

/* ══ Tooltip ══════════════════════════════════════════════════════════════ */
var wolke=$('wolke');

/** Zeigt die Sprechblase bei (x,y) in SEITEN-Koordinaten, also inklusive
 *  Scrollversatz. `y` ist die Oberkante des Punkts, auf den gezeigt wird.
 *
 *  2026-08-07 (vucko): „Beim diagramm sieht man die zahl nicht wenn man
 *  drüber hovert."
 *
 *  Ursache: Die Blase hing starr per CSS-transform translate(-50%,-118%) am
 *  Punkt. Beim letzten Balken ganz rechts ragte die halbe Blasenbreite aus
 *  dem Fenster — und ausgerechnet dort steht der WERT. Sichtbar blieb nur
 *  der Name. Zusaetzlich lag sie mit z-index 30 UNTER der Kopfzeile (40) und
 *  verschwand teilweise dahinter.
 *
 *  Jetzt misst sich die Blase erst selbst und wird dann so gesetzt, dass sie
 *  immer ganz im Bild bleibt: waagrecht an beide Fensterraender begrenzt,
 *  senkrecht nach unten geklappt, wenn oben die Kopfzeile im Weg waere. */
function wolkeZeigen(x,y,html){
  wolke.innerHTML=html;
  // Zum Messen sichtbar machen, aber ohne Sprung: erst positionieren, dann
  // einblenden.
  wolke.style.left='0px';
  wolke.style.top='0px';
  wolke.style.visibility='hidden';
  wolke.classList.add('an');

  var breite=wolke.offsetWidth, hoehe=wolke.offsetHeight;
  var sichtbar=document.documentElement.clientWidth;
  var rand=10;

  var links=x-breite/2;
  var minLinks=window.scrollX+rand;
  var maxLinks=window.scrollX+sichtbar-breite-rand;
  // Ist die Blase breiter als das Fenster (schmales Handy, langer Text),
  // waere maxLinks kleiner als minLinks. Dann lieber links anschlagen als
  // rechts aus dem Bild schieben.
  links = maxLinks<minLinks ? minLinks : Math.max(minLinks,Math.min(maxLinks,links));

  var kopf=document.querySelector('.kopf');
  var kopfUnten=window.scrollY+((kopf&&kopf.getBoundingClientRect().bottom)||0);
  var oben=y-hoehe-12;
  if(oben<kopfUnten+6) oben=y+28;   // kein Platz darueber: darunter zeigen

  wolke.style.left=Math.round(links)+'px';
  wolke.style.top=Math.round(oben)+'px';
  wolke.style.visibility='visible';
}
function wolkeAus(){ wolke.classList.remove('an'); }
document.addEventListener('scroll',wolkeAus,true);

/* ══ Diagramme ════════════════════════════════════════════════════════════
   Alles selbst gezeichnetes SVG. Keine fremde Bibliothek, weil die Seite
   sonst von einem CDN abhinge, das ausfallen oder mitlesen kann.

   Jedes Diagramm bekommt seine Bauanleitung in einer Liste. Wird das Fenster
   gedreht oder skaliert, wird aus derselben Anleitung neu gezeichnet - so
   bleiben Punktgroessen und Strichstaerken korrekt, statt wie vorher per
   preserveAspectRatio="none" verzerrt zu werden.
   ─────────────────────────────────────────────────────────────────────── */
var BAUPLAENE = [];

/* Wird die Seite in einem Hintergrund-Tab oder einer eingeklappten Ansicht
   geladen, ist clientWidth null. Dann zeichnet alles mit der Notbreite 600 —
   und ein spaeteres Aufklappen loest KEIN resize aus, die Diagramme blieben
   also fuer immer falsch skaliert. Der Beobachter unten faengt genau das:
   er meldet jede Groessenaenderung des Behaelters, auch die von null auf
   echte Breite. */
var beobachter = (typeof ResizeObserver!=='undefined') ? new ResizeObserver(function(eintraege){
  eintraege.forEach(function(e){
    var b=BAUPLAENE.filter(function(x){ return x.el===e.target; })[0];
    if(!b) return;
    var neu=Math.round(e.contentRect.width);
    if(neu>40 && Math.abs(neu-(b.zuletzt||0))>8){
      b.zuletzt=neu;
      malen(b.el,b.plan,neu);
    }
  });
}) : null;

function diagramm(behaelter, plan){
  var eintrag={el:behaelter, plan:plan, zuletzt:behaelter.clientWidth||0};
  BAUPLAENE.push(eintrag);
  malen(behaelter, plan);
  if(beobachter) beobachter.observe(behaelter);
}

function malen(behaelter, plan, breiteVorgabe){
  var B=breiteVorgabe||behaelter.clientWidth||600;
  if(B<40) B=600;
  if(plan.typ==='linie'||plan.typ==='balken') malLinieOderBalken(behaelter,plan,B);
  else if(plan.typ==='ring') malRing(behaelter,plan);
}

/** Runde Achsenwerte statt „85,1 / 56,7 / 28,4".
 *
 *  Wichtig ist nicht nur eine runde Schrittweite, sondern dass GENAU `stufen`
 *  Schritte zwischen Unter- und Obergrenze passen. Sonst liegen die Striche
 *  zwar gleichmaessig, tragen aber wieder krumme Zahlen. Deshalb wird die
 *  kleinste bequeme Schrittweite gesucht, mit der die Obergrenze den
 *  Hoechstwert gerade eben ueberdeckt. */
function netteSkala(min,max,stufen,nurGanz){
  if(!(max>min)) return { min:min, max:min+stufen, schritt:1 };
  var grob=(max-min)/stufen;
  var groesse=Math.pow(10,Math.floor(Math.log(grob)/Math.LN10));
  var kandidaten=[1,1.5,2,2.5,3,4,5,6,8,10,15,20];
  for(var i=0;i<kandidaten.length;i++){
    var s=kandidaten[i]*groesse;
    // Stueckzahlen sind ganze Zahlen. „0 / 0,4 / 0,8" waere bei Fahrten
    // je Stunde Unsinn, deshalb dort nur ganzzahlige Schritte.
    if(nurGanz && (s<1 || Math.abs(s-Math.round(s))>1e-9)) continue;
    var u=Math.floor(min/s)*s;
    if(u+s*stufen>=max) return { min:u, max:u+s*stufen, schritt:s };
  }
  return { min:min, max:max, schritt:(max-min)/stufen };
}

/* ── Linie und Balken, beide mit Tooltip ──────────────────────────────── */
function malLinieOderBalken(behaelter, plan, B){
  var reihen=plan.reihen.filter(function(r){ return r.werte && r.werte.length; });
  if(!reihen.length || reihen[0].werte.length<1){
    behaelter.innerHTML='<div class="leer">Noch keine Daten für diesen Zeitraum.</div>';
    return;
  }

  // Zwei Kennzahlen mit ganz verschiedener Groessenordnung auf EINER Achse
  // machen die kleinere zur flachen Linie am Boden. 76 Fahrten neben 1131
  // Kilometern war genau das. Eine Reihe kann deshalb auf die rechte Achse.
  var hatRechts=reihen.some(function(r){ return r.achse==='rechts'; });

  var H=plan.hoehe||180, pL=44, pR=hatRechts?46:12, pO=14, pU=24;
  var breite=B-pL-pR, hoehe=H-pO-pU;
  var n=reihen[0].werte.length;
  var STUFEN=3;

  function grenzen(gruppe){
    var w=[];
    gruppe.forEach(function(r){ r.werte.forEach(function(v){ if(v!==null&&v!==undefined&&!isNaN(v)) w.push(v); }); });
    if(!w.length) return netteSkala(0,1,STUFEN,true);
    var mx=Math.max.apply(null,w), mn=Math.min.apply(null,w);
    // Sind alle Werte ganzzahlig, sind es Stueckzahlen. Dann darf die Achse
    // keine halben Fahrten anschreiben.
    var ganz=w.every(function(v){ return Math.abs(v-Math.round(v))<1e-9; });
    if(plan.abNull!==false) mn=Math.min(0,mn);
    if(mx===mn) mx=mn+1;
    // Kein zusaetzlicher Luftaufschlag: netteSkala rundet die Obergrenze
    // ohnehin schon ueber den Hoechstwert hinaus.
    return netteSkala(mn, mx, STUFEN, ganz);
  }

  var links =grenzen(reihen.filter(function(r){ return r.achse!=='rechts'; }));
  var rechts=hatRechts ? grenzen(reihen.filter(function(r){ return r.achse==='rechts'; })) : links;

  // Der letzte Punkt ist der heutige Tag? Dann ist er nur bis zum letzten
  // Schnappschuss gefuellt und mit den vollen Tagen davor nicht vergleichbar.
  var teilIndex = (plan.teilstandMoeglich!==false && plan.marken && plan.marken.length===n && istHeute(plan.marken[n-1]))
    ? n-1 : -1;

  function X(i){ return n===1 ? pL+breite/2 : pL+(i/(n-1))*breite; }
  function YfuerSkala(sk,v){ return pO+hoehe-((v-sk.min)/(sk.max-sk.min))*hoehe; }
  function Y(r,v){ return YfuerSkala(r.achse==='rechts'?rechts:links, v); }
  var boden=YfuerSkala(links,links.min);

  var s='<svg height="'+H+'" viewBox="0 0 '+B+' '+H+'" role="img">';

  // Farbverlaeufe fuer die Flaechen
  s+='<defs>';
  var flaechenStaerke = reihen.length>1 ? 0.2 : 0.34;
  reihen.forEach(function(r,ri){
    s+='<linearGradient id="fv'+plan.id+ri+'" x1="0" y1="0" x2="0" y2="1">'+
       '<stop offset="0%" stop-color="'+r.farbe+'" stop-opacity="'+flaechenStaerke+'"/>'+
       '<stop offset="100%" stop-color="'+r.farbe+'" stop-opacity="0"/></linearGradient>';
  });
  s+='</defs>';

  // Waagerechte Hilfslinien, links beschriftet, bei zwei Achsen auch rechts
  var farbeLinks =(reihen.filter(function(r){ return r.achse!=='rechts'; })[0]||{}).farbe;
  var farbeRechts=(reihen.filter(function(r){ return r.achse==='rechts'; })[0]||{}).farbe;
  for(var g=0;g<=STUFEN;g++){
    var vL=links.min+((links.max-links.min)*g/STUFEN);
    var yy=YfuerSkala(links,vL);
    s+='<line class="gitter" x1="'+pL+'" y1="'+yy.toFixed(1)+'" x2="'+(B-pR)+'" y2="'+yy.toFixed(1)+'"/>';
    s+='<text class="achse" x="'+(pL-8)+'" y="'+(yy+3.5).toFixed(1)+'" text-anchor="end"'+
       (hatRechts?' fill="'+farbeLinks+'" opacity="0.85"':'')+'>'+kurz(vL)+'</text>';
    if(hatRechts){
      var vR=rechts.min+((rechts.max-rechts.min)*g/STUFEN);
      s+='<text class="achse" x="'+(B-pR+8)+'" y="'+(yy+3.5).toFixed(1)+'" text-anchor="start" fill="'+
         farbeRechts+'" opacity="0.85">'+kurz(vR)+'</text>';
    }
  }

  if(plan.typ==='balken'){
    var lueckeB = n>1 ? (breite/(n-1)) : breite;
    var bw = Math.max(2, Math.min(26, (n>1?lueckeB:breite/2)*0.62/reihen.length));
    // Beschriftung direkt am Balken, solange genug Platz ist. Bei 24 Stunden
    // oder 12 Wochen wuerde sie sich sonst uebereinanderlegen.
    var werteAnschreiben = plan.werteAnschreiben!==false && n<=14 && reihen.length<=2 && bw>=9;
    reihen.forEach(function(r,ri){
      r.werte.forEach(function(v,i){
        if(v===null||v===undefined||isNaN(v)) return;
        var x=X(i)-(bw*reihen.length)/2+ri*bw;
        var y=Y(r,v), h=Math.max(1,boden-y);
        // Der heutige Balken ist ein Teilstand: der Schnappschuss ist von
        // heute frueh, der Tag laeuft noch weiter. Blasser gezeichnet, damit
        // niemand ihn mit einem vollen Tag vergleicht.
        var teil = teilIndex===i;
        s+='<rect class="balken'+(teil?' teil':'')+'" x="'+x.toFixed(1)+'" y="'+y.toFixed(1)+'" width="'+bw.toFixed(1)+
           '" height="'+h.toFixed(1)+'" rx="'+Math.min(3,bw/2).toFixed(1)+'" fill="'+r.farbe+
           '" opacity="'+(teil?'0.42':'0.92')+'"'+(teil?' stroke="'+r.farbe+'" stroke-width="1.2" stroke-dasharray="3 2"':'')+'>'+
           '<animate attributeName="height" from="0" to="'+h.toFixed(1)+'" dur="0.55s" fill="freeze" calcMode="spline" keySplines="0.22 0.9 0.28 1" keyTimes="0;1"/>'+
           '<animate attributeName="y" from="'+boden.toFixed(1)+'" to="'+y.toFixed(1)+'" dur="0.55s" fill="freeze" calcMode="spline" keySplines="0.22 0.9 0.28 1" keyTimes="0;1"/>'+
           '</rect>';
        if(werteAnschreiben && v>0){
          s+='<text class="wertLabel" x="'+(x+bw/2).toFixed(1)+'" y="'+(y-5).toFixed(1)+
             '" text-anchor="middle" fill="'+r.farbe+'">'+kurz(v)+'</text>';
        }
      });
    });
  } else {
    reihen.forEach(function(r,ri){
      var d='';
      for(var i=0;i<r.werte.length;i++){
        var v=r.werte[i]; if(v===null||v===undefined||isNaN(v)) continue;
        d+=(d?' L':'M')+X(i).toFixed(1)+' '+Y(r,v).toFixed(1);
      }
      if(!d) return;
      if(plan.flaeche!==false && n>1){
        var unten=YfuerSkala(r.achse==='rechts'?rechts:links,(r.achse==='rechts'?rechts:links).min);
        s+='<path d="'+d+' L'+X(n-1).toFixed(1)+' '+unten.toFixed(1)+' L'+X(0).toFixed(1)+' '+unten.toFixed(1)+
           ' Z" fill="url(#fv'+plan.id+ri+')" opacity="0">'+
           '<animate attributeName="opacity" from="0" to="1" dur="0.7s" begin="0.2s" fill="freeze"/></path>';
      }
      // Die Linie zeichnet sich einmal selbst. Laenge grosszuegig geschaetzt.
      var laenge=Math.round(breite*1.9);
      s+='<path class="bahn" d="'+d+'" stroke="'+r.farbe+'" stroke-dasharray="'+laenge+'" stroke-dashoffset="'+laenge+'">'+
         '<animate attributeName="stroke-dashoffset" from="'+laenge+'" to="0" dur="0.85s" fill="freeze" calcMode="spline" keySplines="0.3 0.9 0.3 1" keyTimes="0;1"/></path>';
      if(n===1){
        s+='<circle cx="'+X(0).toFixed(1)+'" cy="'+Y(r,r.werte[0]).toFixed(1)+'" r="4" fill="'+r.farbe+'"/>';
      }
      // Auch bei Linien den heutigen, noch unvollstaendigen Punkt kenntlich
      // machen: hohler Ring statt vollem Punkt.
      if(teilIndex>=0 && r.werte[teilIndex]!==null && r.werte[teilIndex]!==undefined){
        s+='<circle cx="'+X(teilIndex).toFixed(1)+'" cy="'+Y(r,r.werte[teilIndex]).toFixed(1)+
           '" r="4" fill="#0a0d14" stroke="'+r.farbe+'" stroke-width="2" stroke-dasharray="2.2 1.8"/>';
      }
    });
  }

  // Zeigerlinie und Punkte, erst beim Zeigen sichtbar
  s+='<line id="zug'+plan.id+'" class="zugLinie" x1="0" y1="'+pO+'" x2="0" y2="'+(pO+hoehe)+'" style="opacity:0"/>';
  reihen.forEach(function(r,ri){
    s+='<circle class="punkt" id="pk'+plan.id+'_'+ri+'" r="4.5" fill="'+r.farbe+'" stroke="#0a0d14" stroke-width="2"/>';
  });

  // Beschriftung unten: hoechstens fuenf, damit nichts uebereinanderliegt
  // So viele Tage anschreiben, wie nebeneinander passen. Frueher waren es
  // starr fuenf, obwohl bei acht Balken alle acht Platz gehabt haetten.
  var marken=plan.marken||[];
  if(marken.length){
    var beispiel=String(plan.markeKurz?plan.markeKurz(marken[0]):marken[0]);
    var proMarke=Math.max(26, beispiel.length*7 + 14);
    var passen=Math.max(2, Math.floor(breite/proMarke));
    var schritt=Math.max(1,Math.ceil(n/passen));
    for(var i2=0;i2<n;i2+=schritt){
      var letzter = i2+schritt>=n;
      var anker = i2===0 ? 'start' : (letzter ? 'end' : 'middle');
      var x2 = i2===0 ? pL : (letzter ? B-pR : X(i2));
      s+='<text class="achse" x="'+x2.toFixed(1)+'" y="'+(H-7)+'" text-anchor="'+anker+'">'+
         esc(plan.markeKurz?plan.markeKurz(marken[i2]):marken[i2])+'</text>';
    }
  }

  s+='<rect id="fang'+plan.id+'" x="'+pL+'" y="'+pO+'" width="'+breite+'" height="'+hoehe+'" fill="transparent" style="cursor:crosshair"/>';
  s+='</svg>';
  behaelter.innerHTML=s;

  /* Tooltip: pointer deckt Maus UND Finger ab. Genau das war der Wunsch,
     „wenn ich auf dem display oder mit der maus auf die anzeige tippe den
     genauen tag haben". */
  var fang=behaelter.querySelector('#fang'+plan.id);
  var zug=behaelter.querySelector('#zug'+plan.id);
  var svgEl=behaelter.querySelector('svg');

  function zeigen(ev){
    var kasten=svgEl.getBoundingClientRect();
    // Ist der Behaelter (noch) null breit — versteckter Tab, eingeklappte
    // Ansicht — waere der Umrechnungsfaktor unendlich und der Index NaN.
    // Achtung: Math.max(0, Math.min(n-1, NaN)) ist NaN, das faengt die
    // Begrenzung unten also NICHT ab. Deshalb hier abbrechen.
    if(!(kasten.width>0)){ wolkeAus(); return; }
    var faktor=B/kasten.width;
    var mx=(ev.clientX-kasten.left)*faktor;
    var i=n===1?0:Math.round(((mx-pL)/breite)*(n-1));
    if(!isFinite(i)) i=n-1;
    i=Math.max(0,Math.min(n-1,i));

    behaelter.classList.add('wach');
    zug.setAttribute('x1',X(i).toFixed(1));
    zug.setAttribute('x2',X(i).toFixed(1));
    zug.style.opacity='1';

    var html='<div class="wTag">'+esc(plan.markeLang?plan.markeLang(marken[i]):(marken[i]||''))+
             (i===teilIndex?' &middot; heute':'')+'</div>';
    reihen.forEach(function(r,ri){
      var p=behaelter.querySelector('#pk'+plan.id+'_'+ri);
      var v=r.werte[i];
      if(v===null||v===undefined||isNaN(v)){ if(p) p.style.opacity='0'; return; }
      if(p){ p.setAttribute('cx',X(i).toFixed(1)); p.setAttribute('cy',Y(r,v).toFixed(1)); p.style.opacity='1'; }
      html+='<div class="wZeile"><i style="background:'+r.farbe+'"></i>'+esc(r.name)+
            '<b>'+(r.formatieren?r.formatieren(v):z(v))+(r.einheit?' '+esc(r.einheit):'')+'</b></div>';
    });
    if(i===teilIndex && DATEN && DATEN.stand){
      html+='<div class="wHinweis">Teilstand bis '+esc(uhrzeit(DATEN.stand))+
            ' Uhr. Der Tag läuft noch, deshalb ist dieser Balken blasser.</div>';
    }

    var y=kasten.top+window.scrollY+pO/faktor;
    wolkeZeigen(kasten.left+window.scrollX+X(i)/faktor, y, html);
  }

  fang.addEventListener('pointermove',zeigen);
  fang.addEventListener('pointerdown',zeigen);
  fang.addEventListener('pointerleave',function(){
    behaelter.classList.remove('wach');
    zug.style.opacity='0';
    wolkeAus();
  });
}

/* ── Ring ─────────────────────────────────────────────────────────────── */
function malRing(behaelter, plan){
  var teile=plan.teile.filter(function(t){ return t.wert>0; });
  var summe=teile.reduce(function(a,t){ return a+t.wert; },0);
  if(!summe){ behaelter.innerHTML='<div class="leer">Keine Daten.</div>'; return; }

  var G=150, r=58, dicke=19, mitte=G/2, umfang=2*Math.PI*r;
  var s='<svg height="'+G+'" viewBox="0 0 '+G+' '+G+'">';
  s+='<circle cx="'+mitte+'" cy="'+mitte+'" r="'+r+'" fill="none" stroke="#222836" stroke-width="'+dicke+'"/>';
  var bisher=0;
  teile.forEach(function(t,i){
    var anteil=t.wert/summe;
    var laenge=anteil*umfang;
    s+='<circle cx="'+mitte+'" cy="'+mitte+'" r="'+r+'" fill="none" stroke="'+t.farbe+'" stroke-width="'+dicke+
       '" stroke-dasharray="'+laenge.toFixed(2)+' '+(umfang-laenge).toFixed(2)+
       '" stroke-dashoffset="'+(-bisher*umfang).toFixed(2)+
       '" transform="rotate(-90 '+mitte+' '+mitte+')" stroke-linecap="butt" opacity="0">'+
       '<animate attributeName="opacity" from="0" to="1" dur="0.45s" begin="'+(i*0.11)+'s" fill="freeze"/></circle>';
    bisher+=anteil;
  });
  s+='<text x="'+mitte+'" y="'+(mitte-2)+'" text-anchor="middle" fill="#eef1f6" font-size="21" font-weight="800">'+z(summe)+'</text>';
  s+='<text x="'+mitte+'" y="'+(mitte+15)+'" text-anchor="middle" fill="#5f6875" font-size="10.5" font-weight="600">'+esc(plan.mitteLabel||'gesamt')+'</text>';
  s+='</svg>';
  behaelter.innerHTML=s;
}

/* ── Rangliste als waagerechte Balken ─────────────────────────────────── */
function rangHtml(eintraege, farbe, einheit){
  if(!eintraege||!eintraege.length) return '<div class="leer">Keine Daten.</div>';
  var max=Math.max.apply(null,eintraege.map(function(e){ return e.wert; }))||1;
  var s='<div class="rang">';
  eintraege.forEach(function(e){
    s+='<div class="rangZeile"><div class="rangKopf"><span>'+esc(e.name)+'</span><b>'+
       (e.text!==undefined?esc(e.text):z(e.wert))+(einheit?' '+esc(einheit):'')+'</b></div>'+
       '<div class="rangBalken"><i style="width:'+((e.wert/max)*100).toFixed(1)+'%;background:'+(e.farbe||farbe)+'"></i></div></div>';
  });
  return s+'</div>';
}

/* ── Heatmap Wochentag mal Stunde ─────────────────────────────────────── */
function heatHtml(punkte){
  if(!punkte||!punkte.length) return '<div class="leer">Keine Daten.</div>';
  var raster={}, max=0;
  punkte.forEach(function(p){
    var d=Number(p.d), h=Number(p.h), c=Number(p.c)||0;
    raster[d+'_'+h]=c;
    if(c>max) max=c;
  });
  if(!max) return '<div class="leer">Noch keine Fahrten erfasst.</div>';

  // Postgres zaehlt den Wochentag ab Sonntag (0). Angezeigt wird ab Montag.
  var reihenfolge=[1,2,3,4,5,6,0];
  var s='<div class="heat">';
  s+='<div></div>';
  for(var h=0;h<24;h++) s+='<div class="hLbl" style="justify-content:center">'+(h%6===0?h:'')+'</div>';
  reihenfolge.forEach(function(d){
    s+='<div class="hLbl">'+wochentage[d]+'</div>';
    for(var h2=0;h2<24;h2++){
      var c=raster[d+'_'+h2]||0;
      var st=c/max;
      var farbe = c===0 ? '#1a1f2b'
        : 'rgba(255,77,36,'+(0.16+st*0.84).toFixed(2)+')';
      s+='<div class="zelle" style="background:'+farbe+'" data-heat="'+wochentage[d]+'|'+h2+'|'+c+'"></div>';
    }
  });
  s+='</div>';
  s+='<div class="heatFuss">wenig <i style="background:rgba(255,77,36,.18)"></i><i style="background:rgba(255,77,36,.45)"></i>'+
     '<i style="background:rgba(255,77,36,.72)"></i><i style="background:rgba(255,77,36,1)"></i> viel'+
     '<span style="margin-left:auto">Spitze: '+z(max)+' Fahrten</span></div>';
  return s;
}

/* ── Gegenueberstellung zweier Zeitraeume ─────────────────────────────────
   Ein gemeinsames Balkendiagramm taugt hier nicht: 167 Kilometer neben
   2 Follows druecken die kleinen Werte auf einen Pixel. Jede Kennzahl wird
   deshalb an SICH SELBST gemessen, nicht an den anderen. */
function vergleichHtml(felder, jetzt, davor){
  var mitVergleich = vergleichAn();
  var s='<div class="rang">';
  felder.forEach(function(f){
    var a=Number(jetzt[f[0]])||0, b=Number(davor[f[0]])||0;
    // Ohne Vergleich zeigt der Balken die Kennzahl an SICH SELBST gemessen,
    // nicht gegen die Vorwoche — sonst waere der Massstab wieder ein Urteil.
    var max=mitVergleich ? Math.max(a,b,1) : Math.max(a,1);
    if(!mitVergleich){
      s+='<div class="rangZeile"><div class="rangKopf"><span>'+esc(f[1])+'</span>'+
         '<b>'+z(a)+'</b></div>'+
         '<div class="rangBalken" style="height:6px"><i style="width:'+((a/max)*100).toFixed(1)+'%;background:'+F.rot+'"></i></div>'+
         '</div>';
      return;
    }
    var p = b>0 ? ((a-b)/b)*100 : (a>0?null:0);
    var kl = p===null ? 'gleich' : (p>1?'hoch':(p<-1?'runter':'gleich'));
    var text = p===null ? 'neu' : (p>0?'↑ +':(p<0?'↓ ':'→ '))+z1(Math.abs(p))+'%';
    s+='<div class="rangZeile"><div class="rangKopf"><span>'+esc(f[1])+'</span>'+
       '<b>'+z(a)+' <small style="color:var(--grau2);font-weight:600">von '+z(b)+'</small> '+
       '<span class="'+kl+'">'+text+'</span></b></div>'+
       '<div class="rangBalken" style="height:6px;margin-bottom:2px"><i style="width:'+((a/max)*100).toFixed(1)+'%;background:'+F.rot+'"></i></div>'+
       '<div class="rangBalken" style="height:6px"><i style="width:'+((b/max)*100).toFixed(1)+'%;background:'+F.grau+'"></i></div>'+
       '</div>';
  });
  return s+'</div>';
}

/* ── Trichter ─────────────────────────────────────────────────────────── */
function trichterHtml(stufen){
  if(!stufen||!stufen.length) return '<div class="leer">Keine Daten.</div>';
  var start=Number(stufen[0].c)||1;
  var farben=[F.blau,F.tuerkis,F.gelb,F.gruen];
  var s='<div class="trichter">';
  stufen.forEach(function(st,i){
    var c=Number(st.c)||0;
    var quote=(c/start)*100;
    var vorher=i>0?(Number(stufen[i-1].c)||0):null;
    var schritt=(vorher&&vorher>0)?((c/vorher)*100):null;
    s+='<div class="tStufe" style="background:rgba(255,255,255,.03)">'+
       '<div class="tFuell" style="background:'+farben[i%farben.length]+';transform:scaleX('+(quote/100).toFixed(3)+')"></div>'+
       '<div class="tInhalt"><div><div class="tName">'+esc(st.k)+'</div>'+
       '<div class="tQuote">'+z1(quote)+'% vom Start'+(schritt!==null?' · '+z1(schritt)+'% vom Schritt davor':'')+'</div></div>'+
       '<div class="tWert">'+z(c)+'</div></div></div>';
  });
  return s+'</div>';
}

/* ── Bindungs-Kohorten ────────────────────────────────────────────────── */
function kohortenHtml(kohorten){
  if(!kohorten||!kohorten.length) return '<div class="leer">Noch keine Kohorten.</div>';
  var maxWoche=0;
  kohorten.forEach(function(k){ (k.cells||[]).forEach(function(c){ if(Number(c.wk)>maxWoche) maxWoche=Number(c.wk); }); });
  var s='<div class="kohorten"><table><thead><tr><th></th><th>Gr&ouml;&szlig;e</th>';
  for(var w=0;w<=maxWoche;w++) s+='<th>W'+w+'</th>';
  s+='</tr></thead><tbody>';
  kohorten.forEach(function(k){
    s+='<tr><td class="name">'+esc(tagKurz(k.cohort)||k.cohort)+'</td><td class="name" style="text-align:right">'+z(k.size)+'</td>';
    for(var w2=0;w2<=maxWoche;w2++){
      var zelle=(k.cells||[]).filter(function(c){ return Number(c.wk)===w2; })[0];
      if(!zelle){ s+='<td class="z" style="background:#12161f;color:#3a4150">·</td>'; continue; }
      var p=Number(zelle.pct)||0;
      var st=Math.min(1,p/100);
      s+='<td class="z" style="background:rgba(46,204,113,'+(0.1+st*0.8).toFixed(2)+')">'+Math.round(p)+'</td>';
    }
    s+='</tr>';
  });
  return s+'</tbody></table></div>';
}

/* ── Uptime-Streifen ──────────────────────────────────────────────────── */
function streifenHtml(pruefungen){
  if(!pruefungen||!pruefungen.length) return '<div class="leer">Noch keine Prüfungen. Die erste läuft zur nächsten vollen Stunde.</div>';
  var sortiert=pruefungen.slice().sort(function(a,b){ return new Date(a.geprueft)-new Date(b.geprueft); });
  var s='<div class="streifen">';
  sortiert.forEach(function(p){
    var farbe=p.up?'#2ecc71':'#FF4D24';
    s+='<i style="background:'+farbe+'" data-heat="'+esc(tagLang(p.geprueft))+'|'+(p.up?'erreichbar':'AUSGEFALLEN')+'|'+(p.ms===null||p.ms===undefined?'–':p.ms+' ms')+'"></i>';
  });
  return s+'</div>';
}

/* Ein einziger Zuhoerer fuer alle Rasterzellen und Streifen. */
document.addEventListener('pointerover',function(e){
  var t=e.target;
  if(!t||!t.getAttribute) return;
  var d=t.getAttribute('data-heat');
  if(!d) return;
  var teile=d.split('|');
  var kasten=t.getBoundingClientRect();
  var html;
  if(teile.length===3 && /ms|erreichbar|AUSGEF/.test(teile[1]+teile[2])){
    html='<div class="wTag">'+esc(teile[0])+'</div><div class="wZeile">'+esc(teile[1])+'<b>'+esc(teile[2])+'</b></div>';
  } else {
    html='<div class="wTag">'+esc(teile[0])+', '+esc(teile[1])+':00 Uhr</div><div class="wZeile">Fahrten<b>'+esc(teile[2])+'</b></div>';
  }
  wolkeZeigen(kasten.left+window.scrollX+kasten.width/2, kasten.top+window.scrollY, html);
});
document.addEventListener('pointerout',function(e){
  if(e.target&&e.target.getAttribute&&e.target.getAttribute('data-heat')) wolkeAus();
});

/* Beim Drehen oder Skalieren aus derselben Bauanleitung neu zeichnen. */
var neuTimer=null;
window.addEventListener('resize',function(){
  clearTimeout(neuTimer);
  neuTimer=setTimeout(function(){
    BAUPLAENE.forEach(function(b){ if(document.body.contains(b.el)) malen(b.el,b.plan); });
  },180);
});

/* ══ Bereiche ═════════════════════════════════════════════════════════════ */
var diaZaehler=0;
/** Legt einen Diagramm-Behaelter an und traegt den Bauplan nach. */
function dia(plan){
  plan.id='d'+(++diaZaehler);
  var kennung='dia_'+plan.id;
  setTimeout(function(){
    var n=$(kennung);
    if(n) diagramm(n,plan);
  },0);
  return '<div class="dia" id="'+kennung+'" style="min-height:'+((plan.hoehe||180))+'px"></div>';
}

function block(titel,inhalt,unter,extra){
  return '<div class="block"><div class="blockKopf"><div><div class="titel">'+esc(titel)+'</div>'+
         (unter?'<div class="untertitel">'+esc(unter)+'</div>':'')+'</div>'+(extra||'')+'</div>'+inhalt+'</div>';
}

/* ── Umschalter je Diagramm ───────────────────────────────────────────────
   2026-08-07 (vucko): „schau bitte das es besser dargestellt wird und man
   zwischen mehr passenden diagrammen wechseln kann."

   Jedes grosse Diagramm bekommt zwei Schalter:
     Pro Tag / Gesamt   was gezeigt wird (Zuwachs oder laufende Summe)
     Balken / Linie / Fläche   wie es gezeigt wird
   Die Wahl merkt sich der Browser je Diagramm und ueberlebt den Wechsel
   des Bereichs und des Zeitraums. */
var WAHL={};
function wahl(schluessel,standard){
  if(!WAHL[schluessel]){
    WAHL[schluessel]={ modus:'proTag', form:'balken' };
    if(standard) for(var k in standard) WAHL[schluessel][k]=standard[k];
  }
  return WAHL[schluessel];
}
function umschalter(schluessel,nurForm){
  var w=wahl(schluessel);
  function gruppe(feld,optionen){
    return '<div class="ugruppe">'+optionen.map(function(o){
      return '<button class="ubtn'+(w[feld]===o[0]?' aktiv':'')+'" data-uschluessel="'+schluessel+
             '" data-ufeld="'+feld+'" data-uwert="'+o[0]+'">'+o[1]+'</button>';
    }).join('')+'</div>';
  }
  return '<div class="umschalter">'+
    (nurForm?'':gruppe('modus',[['proTag','Pro Tag'],['gesamt','Gesamt']]))+
    gruppe('form',[['balken','Balken'],['linie','Linie'],['flaeche','Fläche']])+
  '</div>';
}
document.addEventListener('click',function(e){
  var b=e.target;
  if(!b||!b.getAttribute||!b.getAttribute('data-uschluessel')) return;
  var w=wahl(b.getAttribute('data-uschluessel'));
  w[b.getAttribute('data-ufeld')]=b.getAttribute('data-uwert');
  zeichne();
});

/** Baut aus der Wahl die passende Datenreihe und die Diagrammform. */
function reiheNachWahl(schluessel,pfad,tage){
  var w=wahl(schluessel);
  if(w.modus==='gesamt') return verlaufsReihe(pfad,tage);
  var r=proTagReihe(pfad,tage);
  return r.leer ? verlaufsReihe(pfad,tage) : r;
}
function formNachWahl(schluessel){
  var w=wahl(schluessel);
  return { typ: w.form==='balken'?'balken':'linie', flaeche: w.form==='flaeche' };
}
function untertitelNachWahl(schluessel){
  var w=wahl(schluessel);
  return w.modus==='proTag'
    ? 'Neu an jedem Tag. Zeige auf einen Balken für den genauen Tag.'
    : 'Laufende Gesamtsumme. Zeige auf die Kurve für den genauen Tag.';
}
function namenszusatz(schluessel){
  return wahl(schluessel).modus==='proTag' ? ' an dem Tag' : ' gesamt';
}

function zeichne(){
  if(!DATEN) return;
  // Alte Behaelter abmelden, sonst sammelt der Beobachter mit jedem
  // Bereichswechsel Leichen an.
  if(beobachter) BAUPLAENE.forEach(function(b){ beobachter.unobserve(b.el); });
  BAUPLAENE.length=0;
  wolkeAus();

  var h=(location.hash||'#ueberblick').slice(1);
  if(TITEL[h]) BEREICH=h;
  $('bereichTitel').textContent=TITEL[BEREICH]||'Überblick';
  alle('#nav a').forEach(function(a){
    a.classList.toggle('aktiv', a.getAttribute('href')==='#'+BEREICH);
  });

  var s=spanne();
  $('wTitel').textContent=s.titel;
  $('wZeitraum').textContent=zeitraumText(s);
  $('wVor').disabled = WOCHE_OFFSET===0;

  var m=(DATEN.metrics)||{};
  var out='';

  if(DATEN.__neu && BEREICH==='ueberblick'){
    out+='<div class="hinweis gut">Seit deinem letzten Besuch: <b>+'+z(DATEN.__neu.nutzer)+'</b> Nutzer und <b>+'+
         z(DATEN.__neu.fahrten)+'</b> Fahrten.</div>';
  }
  out+=abdeckungshinweis();

  if(BEREICH==='ueberblick')      out+=bereichUeberblick(m);
  else if(BEREICH==='heute')      out+=bereichHeute(m);
  else if(BEREICH==='leute')      out+=bereichLeute();
  else if(BEREICH==='nutzer')     out+=bereichNutzer(m);
  else if(BEREICH==='fahrten')    out+=bereichFahrten(m);
  else if(BEREICH==='community')  out+=bereichCommunity(m);
  else if(BEREICH==='routing')    out+=bereichRouting(m);
  else if(BEREICH==='infra')      out+=bereichInfra();
  else if(BEREICH==='zugriffe')   out+=bereichZugriffe();

  $('inhalt').innerHTML=out;
  staffeln($('inhalt'));
  nachtragen();
}

function zeitraumText(s){
  var bis=new Date(Date.now()-s.bis*86400000);
  var von=new Date(Date.now()-s.von*86400000);
  return tagKurz(von)+' bis '+tagKurz(bis);
}

function abdeckungshinweis(){
  var ab=DATEN.abdeckung||{};
  if(!ab.aeltester) return '';
  var tage=(Date.now()-new Date(ab.aeltester).getTime())/86400000;
  var noetig = ZEITRAUM==='woche' ? (WOCHE_OFFSET+1)*7 : ZEITRAUM;
  if(tage>=noetig-0.6) return '';
  return '<div class="hinweis">Aufgezeichnet wird seit '+tagKurz(ab.aeltester)+', das sind '+
         Math.floor(tage)+' Tage. Für diesen Filter fehlt noch Verlauf, deshalb rechnet er mit dem ältesten vorhandenen Punkt.</div>';
}

/* ── Kleine Funke-Linie in einer Kennzahlkarte ────────────────────────── */
function funke(pfad,farbe,tage){
  var r=verlaufsReihe(pfad,tage||30);
  if(r.werte.length<2) return '';
  var W=200,H=34,max=Math.max.apply(null,r.werte),min=Math.min.apply(null,r.werte);
  if(max===min) max=min+1;
  var d='';
  for(var i=0;i<r.werte.length;i++){
    var x=(i/(r.werte.length-1))*W;
    var y=H-((r.werte[i]-min)/(max-min))*(H-4)-2;
    d+=(d?' L':'M')+x.toFixed(1)+' '+y.toFixed(1);
  }
  return '<svg class="funke" viewBox="0 0 '+W+' '+H+'" preserveAspectRatio="none">'+
         '<path d="'+d+' L'+W+' '+H+' L0 '+H+' Z" fill="'+farbe+'" opacity="0.1"/>'+
         '<path d="'+d+'" fill="none" stroke="'+farbe+'" stroke-width="1.6" stroke-linejoin="round"/></svg>';
}

/* ── Überblick ───────────────────────────────────────────────────────── */
function bereichUeberblick(m){
  var tage = ZEITRAUM==='woche' ? (WOCHE_OFFSET+1)*7 : ZEITRAUM;
  var rN=reiheNachWahl('ueberblick','users.total',tage);
  var rF=reiheNachWahl('ueberblick','rides.total',tage);

  var o='<div class="raster">'+
    karte('Nutzer gesamt', z(m.users&&m.users.total), deltaHtml('users.total'), funke('users.total',F.blau,tage))+
    karte('Fahrten gesamt', z(m.rides&&m.rides.total), deltaHtml('rides.total'), funke('rides.total',F.rot,tage))+
    karte('Kilometer gesamt', z(m.rides&&m.rides.km_total), deltaHtml('rides.km_total'), funke('rides.km_total',F.gruen,tage))+
    karte('Aktiv heute', z(m.activity&&m.activity.dau), '<div class="fuss">'+z(m.activity&&m.activity.wau)+' die Woche, '+z(m.activity&&m.activity.mau)+' den Monat</div>')+
  '</div>';

  var fU=formNachWahl('ueberblick'), zU=namenszusatz('ueberblick');
  o+=block('Fahrten und Nutzer', dia({
      typ:fU.typ, flaeche:fU.flaeche, hoehe:220, id:0,
      reihen:[
        {name:'Fahrten'+zU, farbe:F.rot,  werte:rF.werte},
        {name:'Nutzer'+zU,  farbe:F.blau, werte:rN.werte}
      ],
      marken:rF.marken.length?rF.marken:rN.marken,
      markeKurz:tagKurz, markeLang:tagKurz
    })+
    '<div class="legende"><span><i style="background:'+F.rot+'"></i>Fahrten</span><span><i style="background:'+F.blau+'"></i>Nutzer</span></div>',
    untertitelNachWahl('ueberblick'), umschalter('ueberblick'));

  // 7 Tage — mit oder ohne Vergleich zur Vorwoche, siehe VERGLEICH oben.
  var v=DATEN.compare;
  if(v && v.cur && v.prev){
    var felder=[['rides','Fahrten'],['km','Kilometer'],['active','Aktive'],['users_new','Neue Nutzer'],
                ['posts','Beiträge'],['comments','Kommentare'],['follows','Follows'],['generations','Routen erzeugt']];
    var mitV = vergleichAn();
    o+=block(mitV ? 'Letzte 7 Tage gegen die 7 davor' : 'Letzte 7 Tage',
      vergleichHtml(felder, v.cur, v.prev)+
      (mitV
        ? '<div class="legende"><span><i style="background:'+F.rot+'"></i>Letzte 7 Tage</span><span><i style="background:'+F.grau+'"></i>7 Tage davor</span></div>'
        : '<div class="legende"><span><i style="background:'+F.rot+'"></i>Letzte 7 Tage</span></div>'),
      mitV ? 'Jede Zeile an sich selbst gemessen, unabhängig vom Filter oben'
           : 'Reine Zahlen der letzten 7 Tage, ohne Wertung gegen die Vorwoche',
      vergleichSchalter());
  }

  o+=block('Routing-Server', infraKurz(), 'Stündlich geprüft');
  return o;
}

/* ── Umschalter „mit / ohne Vorwochen-Vergleich" ─────────────────────────── */
function vergleichSchalter(){
  function b(wert,text){
    return '<button class="ubtn'+(VERGLEICH===wert?' aktiv':'')+'" data-vergleich="'+wert+'">'+text+'</button>';
  }
  return '<div class="umschalter"><div class="ugruppe">'+
         b('vorwoche','Mit Vorwoche')+b('ohne','Ohne Vergleich')+
         '</div></div>';
}
document.addEventListener('click',function(e){
  var b=e.target;
  if(!b||!b.getAttribute||!b.getAttribute('data-vergleich')) return;
  setzeVergleich(b.getAttribute('data-vergleich'));
});

/* ── Heute ────────────────────────────────────────────────────────────────
   2026-08-09 (vucko): eigene Heute-Ansicht. Die Zahlen stammen aus dem
   Schnappschuss, der VIERMAL taeglich entsteht (0/6/12/18 Uhr Wien, siehe
   Migration monitor_vier_schnappschuesse). Es wird also NICHT live gerechnet —
   genau das war die Ursache der Datenbank-Ueberlastung im Juli.

   Deshalb steht der Stand gross oben drueber: „Stand 12:02 Uhr". Wer das nicht
   sieht, haelt eine 6 Stunden alte Zahl fuer den Live-Wert. Der Balken der
   laufenden Stunde ist zwangslaeufig unvollstaendig. */
/* ══ Leute ════════════════════════════════════════════════════════════════
   2026-08-09 (vucko): „ich moechte sehen, wer dazugekommen ist in die App —
   nur mit In-App-Name — und wie viele Personen zuletzt gefahren sind, in einer
   schoenen und klaren und immer geupdateten Ansicht."

   BEWUSST NUR DER IN-APP-NAME. Keine E-Mail, keine ID, kein Standort. Das
   Dashboard ist ein Betriebswerkzeug, kein Personenverzeichnis — und was hier
   nicht steht, kann auch nicht versehentlich weitergegeben werden.

   Die Daten kommen aus demselben 6-Stunden-Schnappschuss wie alles andere und
   kosten keine einzige zusaetzliche Datenbankabfrage. */
function bereichLeute(){
  var L = DATEN.leute;
  if(!L || !L.neue_nutzer){
    return block('Leute','<div class="leer">Dieser Schnappschuss kennt die Ansicht noch nicht. '+
      'Sie fuellt sich beim naechsten Lauf um 0, 6, 12 oder 18 Uhr.</div>');
  }
  var n=L.neue_nutzer||{}, f=L.gefahren||{};

  var o='<div class="raster">'+
    karte('Neu in 24 Stunden', z(n.h24))+
    karte('Neu in 7 Tagen',    z(n.d7))+
    karte('Neu in 30 Tagen',   z(n.d30))+
    karte('Nutzer gesamt',     z(n.gesamt))+
  '</div>';

  o+='<div class="raster" style="margin-top:14px">'+
    karte('Gefahren, 24 Stunden', z(f.personen_h24),
          '<div class="fuss">'+z(f.fahrten_h24)+' Fahrten</div>')+
    karte('Gefahren, 7 Tage',     z(f.personen_d7),
          '<div class="fuss">'+z(f.fahrten_d7)+' Fahrten &middot; '+z(f.km_d7)+' km</div>')+
    karte('Gefahren, 30 Tage',    z(f.personen_d30),
          '<div class="fuss">'+z(f.fahrten_d30)+' Fahrten</div>')+
  '</div>';

  o+=block('Zuletzt dazugekommen', personenTabelle(n.liste, 'seit', function(e){
      return vorWie(e.seit);
    }), 'Die letzten 50 der vergangenen 30 Tage, neueste zuerst');

  o+=block('Zuletzt gefahren', personenTabelle(f.liste, 'zuletzt', function(e){
      return vorWie(e.zuletzt)+' &middot; '+z(e.fahrten)+'&times; &middot; '+z(e.km)+' km';
    }), 'Wer in den letzten 30 Tagen unterwegs war, zuletzt Gefahrene zuerst');

  return o;
}

/** Eine schlichte Namensliste. Zweite Spalte kommt aus [rechts]. */
function personenTabelle(liste, feld, rechts){
  if(!liste || !liste.length) return '<div class="leer">Noch niemand in diesem Zeitraum.</div>';
  var o='<div class="personen">';
  for(var i=0;i<liste.length;i++){
    var e=liste[i];
    o+='<div class="person">'+
         '<span class="pname">'+esc(e.name||'(ohne Namen)')+'</span>'+
         '<span class="pwann">'+rechts(e)+'</span>'+
       '</div>';
  }
  return o+'</div>';
}

function bereichHeute(m){
  var t=DATEN.today;
  if(!t || !t.labels){
    return block('Heute','<div class="leer">Noch kein Schnappschuss für heute. '+
      'Der nächste entsteht um 0, 6, 12 oder 18 Uhr.</div>');
  }
  var k=t.kpi||{};
  var stand=t.generated_at?new Date(t.generated_at):null;
  var standText = stand
    ? 'Stand '+stand.toLocaleTimeString('de-AT',{hour:'2-digit',minute:'2-digit'})+' Uhr'
    : 'Stand unbekannt';

  // Naechster Schnappschuss: das naechste 6-Stunden-Fenster nach dem Stand.
  var naechste='';
  if(stand){
    var h=stand.getHours();
    var n=[0,6,12,18].filter(function(x){ return x>h; })[0];
    naechste = ' · nächste Aktualisierung '+(n===undefined?'0':n)+' Uhr';
  }

  var o='<div class="hinweisZeile" style="margin-bottom:14px;padding:10px 13px;'+
        'background:rgba(255,255,255,.04);border-radius:10px;font-size:12.5px;color:var(--grau)">'+
        '<b style="color:var(--text)">'+esc(standText)+'</b>'+esc(naechste)+
        ' &middot; Viermal am Tag, damit die Datenbank ruhig bleibt.</div>';

  o+='<div class="raster">'+
    karte('Neue Nutzer heute', z(k.users_new))+
    karte('Fahrten heute',     z(k.rides), '<div class="fuss">'+z(k.km)+' km</div>')+
    karte('Aktive heute',      z(k.active))+
    karte('Routen erzeugt',    z(k.generations), '<div class="fuss">'+z(k.posts)+' Beiträge</div>')+
  '</div>';

  var fH=formNachWahl('heuteStunden');
  o+=block('Nach Stunden', dia({
      typ:fH.typ, flaeche:fH.flaeche, hoehe:210, id:0, abNull:true,
      reihen:[
        {name:'Fahrten',      farbe:F.rot,  werte:t.rides||[]},
        {name:'Neue Nutzer',  farbe:F.blau, werte:t.users_new||[]},
        {name:'Routen',       farbe:F.gruen,werte:t.generations||[]},
        {name:'Beiträge',    farbe:F.lila, werte:t.posts||[]}
      ],
      marken:t.labels,
      markeKurz:function(x){ return x; },
      markeLang:function(x){ return x+':00 bis '+x+':59 Uhr'; }
    })+
    '<div class="legende"><span><i style="background:'+F.rot+'"></i>Fahrten</span>'+
    '<span><i style="background:'+F.blau+'"></i>Neue Nutzer</span>'+
    '<span><i style="background:'+F.gruen+'"></i>Routen</span>'+
    '<span><i style="background:'+F.lila+'"></i>Beiträge</span></div>',
    'Seit Mitternacht, Ortszeit Wien', umschalter('heuteStunden',true));

  o+=block('Routing-Server', infraKurz(), 'Stündlich geprüft');
  return o;
}

/* ── Nutzer ──────────────────────────────────────────────────────────── */
function bereichNutzer(m){
  var tage = ZEITRAUM==='woche' ? (WOCHE_OFFSET+1)*7 : ZEITRAUM;
  var u=m.users||{}, a=m.activity||{}, p=m.platforms||{};

  var o='<div class="raster">'+
    karte('Gesamt', z(u.total), deltaHtml('users.total'), funke('users.total',F.blau,tage))+
    karte('Onboarding fertig', z(u.onboarded),
      '<div class="fuss">'+(u.total?z1((u.onboarded/u.total)*100):'–')+'% von allen</div>')+
    karte('Aktiv T/W/M', z(a.dau)+' / '+z(a.wau)+' / '+z(a.mau),
      '<div class="fuss">Haftung '+(a.mau?z1((a.dau/a.mau)*100):'–')+'%</div>')+
    karte('Ø Level', z1(u.avg_level))+
    karte('Neu 24 Stunden', z(u.new_24h))+
    karte('Neu 7 Tage', z(u.new_7d))+
    karte('Mit XP', z(u.with_xp))+
    karte('Gesperrt', z(u.banned))+
  '</div>';

  var r=reiheNachWahl('nutzer','users.total',tage);
  var fN=formNachWahl('nutzer');
  o+=block('Nutzerwachstum', dia({
    typ:fN.typ, flaeche:fN.flaeche, hoehe:200, id:0,
    reihen:[{name:'Nutzer'+namenszusatz('nutzer'), farbe:F.blau, werte:r.werte}],
    marken:r.marken, markeKurz:tagKurz, markeLang:tagKurz
  }), untertitelNachWahl('nutzer'), umschalter('nutzer'));

  // 14 Tage in Tagesaufloesung - der Schnappschuss-Verlauf hat nur zwei
  // Punkte am Tag, trend_14d hat echte Tageswerte.
  if(m.trend_14d && m.trend_14d.length){
    var f14=formNachWahl('trend14');
    o+=block('Neue Nutzer und Fahrten je Tag', dia({
      typ:f14.typ, flaeche:f14.flaeche, hoehe:190, id:0,
      reihen:[
        {name:'Neue Nutzer', farbe:F.blau, werte:m.trend_14d.map(function(d){ return Number(d.users)||0; })},
        {name:'Fahrten',     farbe:F.rot,  werte:m.trend_14d.map(function(d){ return Number(d.rides)||0; })}
      ],
      marken:m.trend_14d.map(function(d){ return d.day; }),
      markeKurz:function(x){ var d=alsDatum(x); return d?String(d.getDate()).padStart(2,'0')+'.'+String(d.getMonth()+1).padStart(2,'0')+'.':x; },
      markeLang:tagKurz
    })+
    '<div class="legende"><span><i style="background:'+F.blau+'"></i>Neue Nutzer</span><span><i style="background:'+F.rot+'"></i>Fahrten</span></div>',
    'Letzte 14 Tage, direkt aus der Datenbank gezählt', umschalter('trend14',true));
  }

  var ringe='<div class="ringBox">'+dia({typ:'ring', id:0, mitteLabel:'Geräte', teile:[
      {name:'iOS', wert:Number(p.ios)||0, farbe:F.blau},
      {name:'Android', wert:Number(p.android)||0, farbe:F.gruen}
    ]})+'<div class="ringLegende">'+
    ringZeile('iOS',p.ios,(Number(p.ios)||0)+(Number(p.android)||0),F.blau)+
    ringZeile('Android',p.android,(Number(p.ios)||0)+(Number(p.android)||0),F.gruen)+
    '</div></div>';
  o+=block('Plattformen', ringe);

  if(m.languages && m.languages.length){
    var farbenS=[F.rot,F.blau,F.gruen,F.gelb,F.lila,F.tuerkis];
    var gesamtS=m.languages.reduce(function(x,l){ return x+(Number(l.c)||0); },0);
    o+=block('Sprachen', '<div class="ringBox">'+
      dia({typ:'ring', id:0, mitteLabel:'Profile', teile:m.languages.map(function(l,i){
        return {name:l.k, wert:Number(l.c)||0, farbe:farbenS[i%farbenS.length]};
      })})+
      '<div class="ringLegende">'+m.languages.map(function(l,i){
        return ringZeile(l.k==='—'?'ohne Angabe':l.k, l.c, gesamtS, farbenS[i%farbenS.length]);
      }).join('')+'</div></div>');
  }

  var an=DATEN.analytics||{};
  if(an.funnel && an.funnel.length){
    o+=block('Vom Start bis zur ersten Fahrt', trichterHtml(an.funnel),
      'Wo Nutzer abspringen');
  }
  if(an.retention && an.retention.length){
    o+=block('Bindung nach Kohorten', kohortenHtml(an.retention),
      'Prozent der Kohorte, die in Woche X noch gefahren ist');
  }

  if(m.geo){
    if(m.geo.countries && m.geo.countries.length){
      o+=block('Länder', rangHtml(m.geo.countries.slice(0,8).map(function(g){
        return {name:g.k||'ohne Angabe', wert:Number(g.c)||0};
      }), F.tuerkis, 'Nutzer'));
    }
    if(m.geo.regions && m.geo.regions.length){
      o+=block('Regionen', rangHtml(m.geo.regions.slice(0,8).map(function(g){
        return {name:g.k||'ohne Angabe', wert:Number(g.c)||0};
      }), F.lila, 'Nutzer'));
    }
  }
  return o;
}
function ringZeile(name,wert,summe,farbe){
  var w=Number(wert)||0;
  return '<div><i style="background:'+farbe+'"></i>'+esc(name)+
         '<b>'+z(w)+'</b><small>'+(summe?z1((w/summe)*100)+'%':'')+'</small></div>';
}

/* ── Fahrten ─────────────────────────────────────────────────────────── */
function bereichFahrten(m){
  var tage = ZEITRAUM==='woche' ? (WOCHE_OFFSET+1)*7 : ZEITRAUM;
  var r=m.rides||{};

  var o='<div class="raster">'+
    karte('Fahrten gesamt', z(r.total), deltaHtml('rides.total'), funke('rides.total',F.rot,tage))+
    karte('Kilometer gesamt', z(r.km_total), deltaHtml('rides.km_total'), funke('rides.km_total',F.gruen,tage))+
    karte('Ø Dauer', z(r.avg_min)+'<span class="einheit">Min</span>')+
    karte('Höchstgeschwindigkeit', z(r.top_speed_max)+'<span class="einheit">km/h</span>',
      '<div class="fuss">im Schnitt '+z(r.top_speed_avg)+' km/h</div>')+
    karte('Heute', z(r.today), '<div class="fuss">'+z(r.km_today)+' km</div>')+
    karte('Letzte 7 Tage', z(r.d7), '<div class="fuss">'+z(r.km_7d)+' km</div>')+
    karte('Fotos', z(r.photos))+
    karte('Ø km je Fahrt', r.total?z1(r.km_total/r.total):'–')+
  '</div>';

  var rf=reiheNachWahl('fahrten','rides.total',tage);
  var rk=reiheNachWahl('fahrten','rides.km_total',tage);
  var fF=formNachWahl('fahrten'), zF=namenszusatz('fahrten');
  // Kilometer auf die rechte Achse: 1131 km neben 76 Fahrten wuerden die
  // Fahrtenkurve sonst zur flachen Linie am Boden pressen.
  o+=block('Fahrten und Kilometer', dia({
    typ:fF.typ, flaeche:fF.flaeche, hoehe:210, id:0,
    reihen:[
      {name:'Fahrten'+zF,   farbe:F.rot,   werte:rf.werte},
      {name:'Kilometer'+zF, farbe:F.gruen, werte:rk.werte, einheit:'km', achse:'rechts'}
    ],
    marken:rf.marken.length?rf.marken:rk.marken, markeKurz:tagKurz, markeLang:tagKurz
  })+
  '<div class="legende"><span><i style="background:'+F.rot+'"></i>Fahrten (Achse links)</span><span><i style="background:'+F.gruen+'"></i>Kilometer (Achse rechts)</span></div>',
  untertitelNachWahl('fahrten')+' Zwei Achsen, weil die Größenordnungen weit auseinanderliegen.',
  umschalter('fahrten'));

  var an=DATEN.analytics||{};
  if(an.heatmap && an.heatmap.length){
    o+=block('Wann gefahren wird', heatHtml(an.heatmap), 'Wochentag mal Stunde, alle erfassten Fahrten');
  }

  if(m.top_km && m.top_km.length){
    o+=block('Meiste Kilometer', rangHtml(m.top_km.map(function(t){
      return {name:t.username||'ohne Namen', wert:Number(t.km)||0, text:z(t.km)};
    }), F.gruen, 'km'));
  }

  if(m.styles && m.styles.length){
    var farben=[F.rot,F.blau,F.gruen,F.gelb,F.lila,F.tuerkis];
    o+=block('Fahrstile', rangHtml(m.styles.map(function(st,i){
      return {name:st.k||st.style||'unbekannt', wert:Number(st.c||st.count)||0, farbe:farben[i%farben.length]};
    }), F.rot));
  }

  if(m.recent && m.recent.length){
    var l='<div class="liste">';
    m.recent.slice(0,8).forEach(function(f){
      l+='<div class="zeile"><i class="ampel" style="background:'+F.rot+'"></i><span>'+esc(f.username||'ohne Namen')+'</span>'+
         '<span class="re">'+z(f.km)+' km'+(f.style?' · '+esc(f.style):'')+'<br>'+
         (f.ago_min!==undefined?'vor '+z(f.ago_min)+' Min':'')+'</span></div>';
    });
    o+=block('Zuletzt gefahren', l+'</div>');
  }

  if(m.garage){
    o+='<div class="raster">'+
      karte('Fahrzeuge in Garagen', z(m.garage.vehicles))+
      karte('Marken', z(m.garage.brands?m.garage.brands.length:0))+
    '</div>';
    if(m.garage.brands && m.garage.brands.length){
      o+=block('Beliebteste Marken', rangHtml(m.garage.brands.slice(0,8).map(function(b){
        return {name:b.k||'unbekannt', wert:Number(b.c)||0};
      }), F.gelb, 'Fahrzeuge'));
    }
  }
  return o;
}

/* ── Community ───────────────────────────────────────────────────────── */
function bereichCommunity(m){
  var tage = ZEITRAUM==='woche' ? (WOCHE_OFFSET+1)*7 : ZEITRAUM;
  var so=m.social||{}, mo=m.moderation||{};

  var o='<div class="raster">'+
    karte('Beiträge', z(so.posts_total), deltaHtml('social.posts_total'), funke('social.posts_total',F.lila,tage))+
    karte('Beiträge 24 Stunden', z(so.posts_24h))+
    karte('Kommentare 24 Stunden', z(so.comments_24h))+
    karte('Follows', z(so.follows), deltaHtml('social.follows'))+
    karte('Gruppen', z(so.groups_total), '<div class="fuss">'+z(so.groups_7d)+' in 7 Tagen</div>')+
    karte('Communities', z(so.communities))+
    karte('Community-Nachrichten', z(so.comm_msgs_24h), '<div class="fuss">letzte 24 Stunden</div>')+
    karte('Push-Geräte aktiv', z(so.tokens_active), '<div class="fuss">von '+z(so.tokens_total)+' registriert</div>')+
  '</div>';

  if(Number(mo.reports_open)>0){
    o+='<div class="hinweis schlimm"><b>'+z(mo.reports_open)+'</b> offene Meldungen warten auf Bearbeitung.</div>';
  } else {
    o+='<div class="hinweis gut">Keine offenen Meldungen.</div>';
  }

  var rp=reiheNachWahl('community','social.posts_total',tage);
  var rf=reiheNachWahl('community','social.follows',tage);
  var fC=formNachWahl('community'), zC=namenszusatz('community');
  o+=block('Beiträge und Follows', dia({
    typ:fC.typ, flaeche:fC.flaeche, hoehe:200, id:0,
    reihen:[
      {name:'Beiträge'+zC, farbe:F.lila,    werte:rp.werte},
      {name:'Follows'+zC,  farbe:F.tuerkis, werte:rf.werte}
    ],
    marken:rp.marken.length?rp.marken:rf.marken, markeKurz:tagKurz, markeLang:tagKurz
  })+
  '<div class="legende"><span><i style="background:'+F.lila+'"></i>Beiträge</span><span><i style="background:'+F.tuerkis+'"></i>Follows</span></div>',
  untertitelNachWahl('community'), umschalter('community'));

  var hi=DATEN.history;
  if(hi && hi.labels && hi.posts){
    o+=block('12 Wochen Community', dia({
      typ:'balken', hoehe:180, id:0,
      reihen:[
        {name:'Beiträge',  farbe:F.lila,    werte:hi.posts},
        {name:'Kommentare', farbe:F.tuerkis, werte:hi.comments||[]}
      ],
      marken:hi.labels,
      markeKurz:function(x){ return x; }, markeLang:function(x){ return 'Woche '+x; }
    })+
    '<div class="legende"><span><i style="background:'+F.lila+'"></i>Beiträge</span><span><i style="background:'+F.tuerkis+'"></i>Kommentare</span></div>',
    'Je Woche neu entstanden');
  }
  return o;
}

/* ── Routing ─────────────────────────────────────────────────────────── */
function bereichRouting(m){
  var tage = ZEITRAUM==='woche' ? (WOCHE_OFFSET+1)*7 : ZEITRAUM;
  var ro=m.routing||{};
  var an=DATEN.analytics||{};
  var rp=an.routing_perf||{};

  var o='<div class="raster">'+
    karte('Routen im Pool', z(ro.pool_size), deltaHtml('routing.pool_size'), funke('routing.pool_size',F.gelb,tage))+
    karte('Davon geprüft', z(ro.pool_verified),
      '<div class="fuss">'+(ro.pool_size?z1((ro.pool_verified/ro.pool_size)*100):'–')+'% des Pools</div>')+
    karte('Städte abgedeckt', z(ro.pool_cities))+
    karte('Ø Qualität', z1(ro.avg_quality))+
    karte('Erzeugt 24 Stunden', z(ro.gen_24h))+
    karte('Erzeugt 7 Tage', z(ro.gen_7d))+
    karte('Antwort p50', rp.p50_24h!==undefined?z(rp.p50_24h)+'<span class="einheit">ms</span>':'–',
      '<div class="fuss">letzte 24 Stunden</div>')+
    karte('Antwort p95', rp.p95_24h!==undefined?z(rp.p95_24h)+'<span class="einheit">ms</span>':'–',
      '<div class="fuss">7 Tage: '+(rp.p95_7d!==undefined?z(rp.p95_7d)+' ms':'–')+'</div>')+
  '</div>';

  if(rp.err_rate_24h!==undefined && rp.err_rate_24h!==null){
    var q=Number(rp.err_rate_24h);
    var kl = q>5?'schlimm':(q>1?'':'gut');
    o+='<div class="hinweis '+kl+'">Fehlerquote bei der Routenerzeugung: <b>'+z1(q)+'%</b> in den letzten 24 Stunden'+
       (rp.err_rate_7d!==undefined?', <b>'+z1(rp.err_rate_7d)+'%</b> über 7 Tage':'')+
       (rp.total_7d!==undefined?' bei '+z(rp.total_7d)+' Anfragen':'')+'.</div>';
  }

  var rpool=reiheNachWahl('routing','routing.pool_size',tage);
  var fR=formNachWahl('routing');
  o+=block('Pool-Entwicklung', dia({
    typ:fR.typ, flaeche:fR.flaeche, hoehe:190, id:0,
    reihen:[{name:'Routen im Pool'+namenszusatz('routing'), farbe:F.gelb, werte:rpool.werte}],
    marken:rpool.marken, markeKurz:tagKurz, markeLang:tagKurz
  }), untertitelNachWahl('routing'), umschalter('routing'));

  var hi=DATEN.history;
  if(hi && hi.labels && hi.generations){
    o+=block('12 Wochen Routenerzeugung', dia({
      typ:'balken', hoehe:175, id:0,
      reihen:[{name:'Erzeugt', farbe:F.rot, werte:hi.generations}],
      marken:hi.labels, markeKurz:function(x){ return x; }, markeLang:function(x){ return 'Woche '+x; }
    }));
  }

  if(m.styles && m.styles.length){
    var farben=[F.rot,F.blau,F.gruen,F.gelb,F.lila,F.tuerkis];
    o+=block('Nachgefragte Fahrstile', rangHtml(m.styles.map(function(st,i){
      return {name:st.k||st.style||'unbekannt', wert:Number(st.c||st.count)||0, farbe:farben[i%farben.length]};
    }), F.rot));
  }
  return o;
}

/* ── Infrastruktur ───────────────────────────────────────────────────── */
function infraKurz(){
  var hosts=(DATEN.infra&&DATEN.infra.hosts)||[];
  if(!hosts.length) return '<div class="leer">Noch keine Prüfung.</div>';
  var s='<div class="liste">';
  hosts.forEach(function(h){
    var lebt=h.up===true;
    s+='<div class="zeile"><i class="ampel'+(lebt?' lebt':'')+'" style="background:'+(lebt?F.gruen:F.rot)+'"></i>'+
       '<span>'+esc(h.anzeige)+'</span><span class="re">'+
       (lebt ? z(h.ms)+' ms' : 'nicht erreichbar')+'</span></div>';
  });
  return s+'</div>';
}

function bereichInfra(){
  var infra=DATEN.infra||{};
  var hosts=infra.hosts||[];
  var pruef=infra.verlauf||[];
  var o='';

  var tot=hosts.filter(function(h){ return h.up===false; });
  if(tot.length){
    o+='<div class="hinweis schlimm"><b>'+tot.length+' von '+hosts.length+' Routing-Servern ausgefallen.</b><br>'+
       tot.map(function(h){ return esc(h.anzeige)+' seit '+dauerSeit(h.seit)+(h.letzter_fehler?' ('+esc(h.letzter_fehler)+')':''); }).join('<br>')+
       '</div>';
  } else if(hosts.length){
    o+='<div class="hinweis gut">Beide Routing-Server antworten. Geprüft wird stündlich, ein Ausfall wird sofort als Push gemeldet.</div>';
  }

  hosts.forEach(function(h){
    var lebt=h.up===true;
    var eigene=pruef.filter(function(p){ return p.host===h.host; });
    var letzte24=eigene.slice(0,24);
    var quote24=letzte24.length?(letzte24.filter(function(p){ return p.up; }).length/letzte24.length)*100:null;
    var quoteAlle=eigene.length?(eigene.filter(function(p){ return p.up; }).length/eigene.length)*100:null;
    var msWerte=eigene.filter(function(p){ return p.up && p.ms!==null; }).map(function(p){ return p.ms; });
    var msSchnitt=msWerte.length?msWerte.reduce(function(a,b){ return a+b; },0)/msWerte.length:null;

    var karteHtml='<div class="hostKarte'+(lebt?'':' tot')+'">'+
      '<div class="hostKopf"><i class="ampel'+(lebt?' lebt':'')+'" style="background:'+(lebt?F.gruen:F.rot)+'"></i>'+
      '<b>'+esc(h.anzeige)+'</b><span class="re" style="color:'+(lebt?F.gruen:F.rot)+'">'+
      (lebt?z(h.ms)+' ms':'ausgefallen')+'</span></div>'+
      '<div class="hostZeile"><span>Zustand seit</span><b>'+dauerSeit(h.seit)+'</b></div>'+
      '<div class="hostZeile"><span>Zuletzt geprüft</span><b>'+esc(vorWie(h.zuletzt_geprueft))+'</b></div>'+
      (quote24!==null?'<div class="hostZeile"><span>Erreichbar letzte 24 Prüfungen</span><b>'+z1(quote24)+'%</b></div>':'')+
      (quoteAlle!==null?'<div class="hostZeile"><span>Erreichbar gesamt</span><b>'+z1(quoteAlle)+'% von '+eigene.length+'</b></div>':'')+
      (msSchnitt!==null?'<div class="hostZeile"><span>Ø Antwortzeit</span><b>'+z(msSchnitt)+' ms</b></div>':'')+
      (h.letzter_fehler?'<div class="hostZeile"><span>Letzter Fehler</span><b>'+esc(h.letzter_fehler)+'</b></div>':'')+
      '<div style="margin-top:9px"><div class="hostZeile" style="padding-bottom:6px"><span>Geladene Profile</span><b>'+
        (h.profile&&h.profile.length?h.profile.length:'–')+'</b></div>'+
        (h.profile&&h.profile.length
          ? h.profile.map(function(p){ return '<span class="marke2'+(p==='car'?' gut':'')+'">'+esc(p)+'</span>'; }).join('')
          : '<span class="marke2 warn">keine gelesen</span>')+
      '</div>'+
      (eigene.length?'<div style="margin-top:12px"><div class="titel" style="margin-bottom:6px">Erreichbarkeit</div>'+streifenHtml(eigene.slice(0,72))+'</div>':'')+
    '</div>';
    o+=karteHtml;
  });

  // Fehlt ein Profil, das der andere hat? Dann ist der Ausweichserver
  // kein vollwertiger Ersatz. Genau das ist bei PC1 der Fall: kein car.
  if(hosts.length===2 && hosts[0].profile && hosts[1].profile){
    var a=hosts[0], b=hosts[1];
    var fehltBeiA=b.profile.filter(function(p){ return a.profile.indexOf(p)<0; });
    var fehltBeiB=a.profile.filter(function(p){ return b.profile.indexOf(p)<0; });
    if(fehltBeiA.length||fehltBeiB.length){
      o+='<div class="hinweis"><b>Die beiden Server können nicht dasselbe.</b><br>'+
        (fehltBeiA.length?esc(a.anzeige)+' fehlt: '+fehltBeiA.map(esc).join(', ')+'<br>':'')+
        (fehltBeiB.length?esc(b.anzeige)+' fehlt: '+fehltBeiB.map(esc).join(', ')+'<br>':'')+
        'Fällt einer aus, kann der andere nicht jede Anfrage übernehmen.</div>';
    }
  }

  // Antwortzeiten als Kurve
  var proHost={};
  pruef.forEach(function(p){ (proHost[p.host]=proHost[p.host]||[]).push(p); });
  var namen=Object.keys(proHost);
  if(namen.length){
    var farbenH=[F.blau,F.rot];
    var basis=proHost[namen[0]].slice().sort(function(x,y){ return new Date(x.geprueft)-new Date(y.geprueft); });
    o+=block('Antwortzeiten', dia({
      typ:'linie', hoehe:180, id:0, abNull:true, flaeche:false,
      reihen:namen.map(function(nm,i){
        var reihe=proHost[nm].slice().sort(function(x,y){ return new Date(x.geprueft)-new Date(y.geprueft); });
        var anzeige=(hosts.filter(function(h){ return h.host===nm; })[0]||{}).anzeige||nm;
        return {name:anzeige, farbe:farbenH[i%farbenH.length], einheit:'ms',
                werte:reihe.map(function(p){ return p.up?p.ms:null; })};
      }),
      marken:basis.map(function(p){ return p.geprueft; }),
      markeKurz:function(x){ var d=alsDatum(x); return d?String(d.getHours()).padStart(2,'0')+':00':''; },
      markeLang:tagLang
    })+
    '<div class="legende">'+namen.map(function(nm,i){
      var anzeige=(hosts.filter(function(h){ return h.host===nm; })[0]||{}).anzeige||nm;
      return '<span><i style="background:'+farbenH[i%farbenH.length]+'"></i>'+esc(anzeige)+'</span>';
    }).join('')+'</div>',
    'Lücken in der Linie sind Ausfälle',
    '<button class="knopfKlein" id="knopfPruefen">Jetzt prüfen</button>');
  } else {
    o+=block('Antwortzeiten','<div class="leer">Noch keine Prüfungen gespeichert. Die erste läuft zur nächsten vollen Stunde plus 13 Minuten.</div>',
      '', '<button class="knopfKlein" id="knopfPruefen">Jetzt prüfen</button>');
  }

  var st=(DATEN.metrics||{}).stability||{};
  if(st.connected){
    o+='<div class="raster">'+
      karte('Fehler 24 Stunden', z(st.errors_24h))+
      karte('Abstürze 24 Stunden', z(st.fatal_24h))+
      karte('Abstürze 7 Tage', z(st.fatal_7d))+
      karte('Betroffene 7 Tage', z(st.affected_7d))+
    '</div>';
  } else {
    o+='<div class="hinweis">Die App meldet noch keine Fehler an die Datenbank. Die Tabelle dafür steht, es schreibt nur niemand hinein.</div>';
  }
  return o;
}

/* ── Zugriffe ────────────────────────────────────────────────────────── */
function bereichZugriffe(){
  var o='<div class="hinweis gut">Angemeldet als <b>'+esc(DATEN.angemeldet_als||NAME)+'</b>. '+
        'Die Sitzung endet beim Schließen des Browsers.</div>';

  o+='<div class="raster">'+
    karte('Schnappschüsse', z((DATEN.abdeckung||{}).punkte))+
    karte('Aufzeichnung seit', tagKurz((DATEN.abdeckung||{}).aeltester))+
    karte('Letzter Stand', tagKurz(DATEN.stand), '<div class="fuss">'+esc(vorWie(DATEN.stand))+'</div>')+
    karte('Halbtag', esc(DATEN.slot||'–'))+
  '</div>';

  o+=block('Wie dieses Dashboard die Datenbank schont',
    '<div class="liste">'+
    '<div class="zeile"><i class="ampel" style="background:'+F.gruen+'"></i><span>Berechnet wird zweimal am Tag per pg_cron</span><span class="re">10:00 und 22:00 UTC</span></div>'+
    '<div class="zeile"><i class="ampel" style="background:'+F.gruen+'"></i><span>Ein Dashboard-Aufruf macht drei indizierte SELECTs</span><span class="re">keine Berechnung</span></div>'+
    '<div class="zeile"><i class="ampel" style="background:'+F.gruen+'"></i><span>Filter, Bereiche und Wochenvergleich rechnen im Browser</span><span class="re">keine Abfrage</span></div>'+
    '<div class="zeile"><i class="ampel" style="background:'+F.gruen+'"></i><span>Mini-PCs werden stündlich geprüft, nicht bei jedem Aufruf</span><span class="re">48 Zeilen am Tag</span></div>'+
    '</div>',
    'Der Grund: einmal hat das Werkzeug 13,5-fach zu oft gerechnet');

  o+=block('Schutz des Zugangs',
    '<div class="liste">'+
    '<div class="zeile"><i class="ampel" style="background:'+F.gruen+'"></i><span>Passwörter liegen als bcrypt-Hash in der Datenbank</span></div>'+
    '<div class="zeile"><i class="ampel" style="background:'+F.gruen+'"></i><span>Fehlversuche werden protokolliert, danach 15 Minuten Sperre</span></div>'+
    '<div class="zeile"><i class="ampel" style="background:'+F.gruen+'"></i><span>Bei Häufung geht eine Push-Meldung an Vucko und Luca</span></div>'+
    '<div class="zeile"><i class="ampel" style="background:'+F.gruen+'"></i><span>Die Konten sind von der App getrennt und fälschen keine Kennzahlen</span></div>'+
    '<div class="zeile"><i class="ampel" style="background:'+F.gruen+'"></i><span>Solange das Startpasswort gilt, gibt der Server keine Zahlen heraus</span></div>'+
    '</div>');

  return o;
}

/* ── Nach dem Einsetzen: Knoepfe verdrahten ──────────────────────────── */
function nachtragen(){
  var p=$('knopfPruefen');
  if(p){
    p.addEventListener('click',function(){
      if(LAEUFT) return;
      LAEUFT=true;
      p.disabled=true;
      p.innerHTML='<span class="dreher"></span> prüfe';
      ruf({aktion:'infra_jetzt',token:TOKEN}).then(function(a){
        LAEUFT=false;
        if(a.infra) DATEN.infra=a.infra;
        if(a.grund==='zu_frueh'){
          melde('Gerade eben schon geprüft. In '+a.wartesekunden+' Sekunden wieder möglich.');
        } else if(a.ok){
          melde('Beide Server frisch geprüft.');
        } else {
          melde('Prüfung nicht durchgekommen.',true);
        }
        kopfFuellen();
        zeichne();
      }).catch(function(){
        LAEUFT=false; p.disabled=false; p.textContent='Jetzt prüfen';
        melde('Prüfung fehlgeschlagen.',true);
      });
    });
  }
}

/* ── CSV ─────────────────────────────────────────────────────────────── */
$('knopfExport').addEventListener('click',function(){
  if(!DATEN||!DATEN.verlauf){ melde('Noch keine Daten.'); return; }
  var spalten=[['users.total','Nutzer'],['rides.total','Fahrten'],['rides.km_total','Kilometer'],
               ['activity.dau','Aktiv heute'],['social.posts_total','Beitraege'],
               ['social.follows','Follows'],['routing.pool_size','Pool']];
  var zeilen=[['Zeitpunkt'].concat(spalten.map(function(s){ return s[1]; })).join(';')];
  DATEN.verlauf.slice().reverse().forEach(function(p){
    zeilen.push([p.t].concat(spalten.map(function(s){
      var w=wertAus(p.m,s[0]);
      return w===null?'':String(w).replace('.',',');
    })).join(';'));
  });
  var text='﻿'+zeilen.join('\n');
  var a=document.createElement('a');
  a.href=URL.createObjectURL(new Blob([text],{type:'text/csv;charset=utf-8'}));
  a.download='cruiseconnector-monitoring.csv';
  a.click();
  setTimeout(function(){ URL.revokeObjectURL(a.href); },2000);
  melde('CSV geladen.');
});

})();
