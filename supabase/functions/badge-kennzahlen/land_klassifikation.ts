// Laender-Klassifikation fuer die Abzeichen-Kennzahlen.
//
// 2026-09-01 — Neue Badge-Familie "Laender" (badge_77 bis badge_79) aus der
// Figma-Serie. Vuckos Vorgabe: "serverseitige Laender-Klassifikation
// verwenden, NICHT den Client entscheiden lassen".
//
// WARUM HIER EINE KOPIE STEHT, und warum das vertretbar ist:
//
// Dieselbe Klassifikation gibt es schon zweimal — in
// lib/data/services/country_region.dart und in
// generate-cruise-route-v2/index.ts. CLAUDE.md verlangt ausdruecklich, dass
// beide zeichengleich rechnen, und der Waechter
// test/route/laender_klassifikation_test.dart prueft das an 36 echten Orten.
//
// Die Alternative waere gewesen, die Funktionen aus der Routing-Funktion
// herauszuloesen und von beiden Stellen zu importieren. Das ist der sauberere
// Weg, faellt aber mitten in die Routing-Funktion — die Datei, die am selben
// Tag schon fuer den Kehrtwenden-Fix geaendert wurde und die Vucko
// ausdruecklich als wichtigstes Stueck benannt hat. Fuer ein Abzeichen ist
// mir das Risiko zu gross.
//
// Stattdessen ist der Waechtertest auf DREI Fassungen erweitert. Laufen sie
// auseinander, faellt er. Die Herausloesung gehoert nachgeholt, sobald die
// Routing-Funktion aus einem anderen Grund ohnehin angefasst wird.
//
// ZEICHENGLEICH UEBERNOMMEN aus generate-cruise-route-v2/index.ts.

function croatiaNorthLimit(lng: number): number {
  if (lng < 13.58) return 45.48;
  if (lng < 14.00) return 45.47;
  if (lng < 14.60) return 45.50;
  if (lng < 14.80) return 45.45;
  if (lng < 15.10) return 45.40;
  if (lng < 15.40) return 45.45;
  if (lng < 15.70) return 45.88;
  if (lng < 15.75) return 46.25;
  if (lng < 16.20) return 46.30;
  if (lng < 16.30) return 46.35;
  if (lng < 16.60) return 46.56;
  if (lng < 17.20) return 46.40;
  if (lng < 18.90) return 45.84;
  return 45.70;
}

function croatiaSouthLimit(lng: number): number {
  if (lng < 14.40) return 44.35;
  if (lng < 14.80) return 44.40;
  if (lng < 15.30) return 44.70;
  if (lng < 15.75) return 44.30;
  if (lng < 16.60) return 45.05;
  if (lng < 17.30) return 45.05;
  if (lng < 18.20) return 45.05;
  return 44.95;
}

// 2026-08-25 (vucko): Grobe Kroatien-Erkennung. Kroatien ist eine Sichel um
// Bosnien herum — eine Box wuerde Sarajevo, Mostar und Podgorica mit
// einschliessen. Daher ein kontinentaler Teil mit laengen-abhaengiger Sued-
// UND Nordgrenze plus ein schmaler dalmatinischer Kuestenstreifen, der nach
// Sueden enger wird (Trebinje BA und Herceg Novi ME liegen dicht an
// Dubrovnik). Beide Bandtabellen MUESSEN zeichengleich in
// `_croatiaNorthLimit` / `_croatiaSouthLimit` von country_region.dart stehen.

function pointInPolygon(lat: number, lng: number, polygon: Array<[number, number]>): boolean {
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const [xi, yi] = polygon[i];
    const [xj, yj] = polygon[j];
    const intersects = ((yi > lat) !== (yj > lat)) &&
      (lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi);
    if (intersects) inside = !inside;
  }
  return inside;
}

function vorarlbergWestLimit(lat: number): number {
  if (lat >= 47.50) return 9.70;
  if (lat >= 47.44) return 9.645;
  if (lat >= 47.32) return 9.585;
  if (lat >= 47.22) return 9.565;
  if (lat >= 47.15) return 9.600;
  return 9.650;
}

function austriaNorthLimit(lng: number): number {
  if (lng < 10.9) return 47.55;
  if (lng < 11.6) return 47.42;
  if (lng < 12.6) return 47.60;
  if (lng < 13.4) return 47.82;
  return 48.80;
}

// 2026-08-18 (D1b2, gemessen): Die alte IT-Box `lat < 46.85 && lng 6.6..13.9`
// verschluckte GANZ Osttirol und den Westen Kaerntens, die SI-Box
// `lat 45.4..46.9 && lng 13.4..16.6` den Rest Kaerntens. Gemessen an der
// Produktions-Edge: Villach (46.610/13.856) -> IT, Lienz (46.830/12.769) -> IT,
// Klagenfurt (46.625/14.308) -> SI. Fuer diese Nutzer war „Im Land bleiben"
// unbenutzbar, sobald irgendjemand die Laenderkennung korrekt setzt.
//
// Die Suedgrenze Oesterreichs laeuft nicht auf einer Breite, sondern springt
// entlang des Alpenhauptkamms. Diese Bandtabelle folgt den realen
// Grenzuebergaengen: Reschen 46.84, Brenner 47.00, Innichen/Sillian 46.73,
// Ploeckenpass 46.60, Nassfeld 46.56, Thoerl-Maglern 46.52, Loibl 46.43,
// Seebergsattel 46.47, Radlpass 46.66, Spielfeld 46.70.
// Alles NOERDLICH der Bandgrenze ist Oesterreich und darf nicht mehr in die
// IT- oder SI-Box fallen.
function austriaSouthLimit(lng: number): number {
  if (lng < 11.00) return 46.85; // Reschenpass / Vinschgau
  if (lng < 12.00) return 46.90; // Brenner, Timmelsjoch
  if (lng < 12.35) return 46.78; // Innichen bleibt Italien
  if (lng < 12.60) return 46.68; // Sillian, Kartitsch = Osttirol
  if (lng < 13.50) return 46.55; // Ploeckenpass, Nassfeld
  if (lng < 13.75) return 46.53; // Thoerl-Maglern: Arnoldstein AT / Tarvis IT
  if (lng < 14.20) return 46.45; // Karawankentunnel: Villach AT / Jesenice SI
  if (lng < 14.60) return 46.44; // Loibl: Ferlach AT
  if (lng < 14.90) return 46.47; // Seebergsattel, Koralpe
  if (lng < 15.50) return 46.62; // Drau: Lavamuend AT / Dravograd SI
  if (lng < 15.80) return 46.695; // Mur: Spielfeld/Mureck AT, Sentilj SI
  return 46.683; // Mur: Bad Radkersburg AT, Gornja Radgona SI
}

function isCroatiaApprox(lat: number, lng: number): boolean {
  if (lng >= 13.45 && lng <= 19.45 &&
      lat >= croatiaSouthLimit(lng) && lat <= croatiaNorthLimit(lng)) {
    return true;
  }
  if (lng < 14.80 || lng > 18.45) return false;
  const mitte = 44.30 - (lng - 14.80) * 0.47;
  const oben = lng >= 17.60 ? 0.00 : 0.42;
  return lat >= mitte - 0.35 && lat <= mitte + oben;
}

function isLiechtensteinApprox(lat: number, lng: number): boolean {
  if (lat < 47.04 || lat > 47.28 || lng < 9.47 || lng > 9.64) return false;
  return pointInPolygon(lat, lng, [
    [9.485, 47.270],
    [9.545, 47.270],
    [9.585, 47.235],
    [9.626, 47.165],
    [9.615, 47.047],
    [9.490, 47.045],
    [9.485, 47.165],
  ]);
}

function isVorarlbergAustria(lat: number, lng: number): boolean {
  if (lat < 46.82 || lat > 47.56 || lng < 9.52 || lng > 10.30) return false;
  if (isLiechtensteinApprox(lat, lng)) return false;
  return lng >= vorarlbergWestLimit(lat);
}

function classifyCountry(lat: number, lng: number): string | null {
  if (isLiechtensteinApprox(lat, lng)) return 'LI';
  if (lat >= 47.52 && lat <= 47.58 && lng >= 9.63 && lng <= 9.74) return 'DE';
  if (isVorarlbergAustria(lat, lng)) return 'AT';
  if (lat >= 45.80 && lat <= 47.81 && lng >= 5.95 && lng <= 9.66) return 'CH';
  // Oesterreich-Sued VOR IT/SI pruefen — sonst gewinnen die groben Boxen.
  if (lng >= 10.00 && lng <= 17.16 && lat >= austriaSouthLimit(lng) &&
      lat <= austriaNorthLimit(lng)) {
    return 'AT';
  }
  // 2026-08-25 (vucko, Feld-Kommentar aus Kroatien): Kroatien fehlte hier
  // ebenso wie im Client. Ergebnis: In Nord-/Innerstistrien wurde ein
  // komplett kroatischer Rundkurs mit `no_inland_route` abgewiesen, weil das
  // Stueck oestlich von lng 13.9 als Slowenien galt. VOR IT/SI pruefen.
  if (isCroatiaApprox(lat, lng)) return 'HR';
  // Ostgrenze fuer IT: die Box verschluckte sonst Koper und Piran (SI).
  if (lat < 46.85 && lng >= 6.6 && lng <= 13.9 &&
      !(lng > 13.40 && lat >= 45.40 && lat < 45.58)) return 'IT';
  if (lat >= 45.4 && lat <= 46.9 && lng >= 13.4 && lng <= 16.6) return 'SI';
  if (lng >= 9.53 && lng <= 17.16 && lat >= 46.37) {
    if (lat <= austriaNorthLimit(lng)) return 'AT';
  }
  if (lat >= 47.27 && lat <= 55.06 && lng >= 5.87 && lng <= 15.04) return 'DE';
  return null;
}

// 2026-08-25 (vucko): Grobe Kroatien-Erkennung. Kroatien ist eine Sichel um
// Bosnien herum — eine Box wuerde Sarajevo, Mostar und Podgorica mit
// einschliessen. Daher ein kontinentaler Teil mit laengen-abhaengiger Sued-
// UND Nordgrenze plus ein schmaler dalmatinischer Kuestenstreifen, der nach
// Sueden enger wird (Trebinje BA und Herceg Novi ME liegen dicht an
// Dubrovnik). Beide Bandtabellen MUESSEN zeichengleich in
// `_croatiaNorthLimit` / `_croatiaSouthLimit` von country_region.dart stehen.
export { classifyCountry };
