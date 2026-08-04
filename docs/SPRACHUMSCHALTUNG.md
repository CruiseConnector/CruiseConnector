# Sprachumschaltung Deutsch / English

Stand: 2026-08-03 · Branch `feature/sprachauswahl-de-en`

## Was funktioniert

Beim **allerersten** App-Start erscheint die Sprachwahl (vorbelegt mit der
Geräte-Sprache), danach nie wieder. Ändern über **Einstellungen → Sprache** —
der Wechsel greift sofort, ohne Neustart.

| Baustein | Datei |
|---|---|
| Sprachwahl beim Erststart | `lib/presentation/pages/language_choice_page.dart` |
| Umschalter in den Einstellungen | `lib/presentation/widgets/language_picker.dart` |
| Zustand + Speicherung | `lib/application/providers/app_locale_provider.dart` |
| Kurzzugriff `context.l10n` | `lib/core/l10n_extension.dart` |
| Texte | `lib/l10n/app_de.arb` (Vorlage) + `app_en.arb` |
| Konfiguration | `l10n.yaml` |

Der `AppLocaleProvider` folgt exakt dem Muster von `AppAccentProvider` —
`ChangeNotifier` + `shared_preferences`, wie alle App-Einstellungen hier.

## Vollständigkeit wird maschinell geprüft

Bei rund **1.900 Textstellen in 98 Dateien** kann kein Mensch nachhalten, was
schon übersetzt ist. Drei Wächter übernehmen das:

1. `l10n.yaml` schreibt bei jedem Build nach `untranslated.json`, welcher
   Schlüssel im Englischen fehlt.
2. `test/l10n/arb_completeness_test.dart` schlägt fehl bei fehlenden,
   verwaisten oder leeren Schlüsseln — und erkennt längere Sätze, die im
   Englischen wortgleich zum Deutschen geblieben sind (= vergessen).
3. `flutter analyze` nach jeder Welle.

## Mail-Templates zweisprachig

Supabase erlaubt nur **ein** Template pro Mail-Typ. Darum beide Sprachen
untereinander, Englisch zuerst nur dort, wo es der internationalen Erwartung
entspricht — sonst Deutsch oben, weil die Mehrheit der Nutzer deutschsprachig
ist. Einzutragen unter **Authentication → Email Templates**.

Beide Templates behalten das bestehende Layout (gleiche Schrift, Farben,
Code-Kachel) und bekommen den englischen Text darunter.

**Der Code steht bewusst nur EINMAL** in der Mail, zwischen beiden
Sprachblöcken. Zwei Code-Kacheln mit derselben Ziffernfolge lesen sich wie zwei
verschiedene Codes — genau die Verwirrung, die man in einer Bestätigungsmail
nicht braucht.

### Confirm signup

Betreff: `Dein Bestätigungscode · Your confirmation code`

```html
<div style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;max-width:480px;margin:0 auto;padding:8px">
  <h2 style="color:#0B0E14;margin:0 0 6px;font-weight:800">Willkommen bei Cruise Connector</h2>
  <p style="color:#3a4152;margin:0 0 18px;line-height:1.5">Danke für deine Registrierung! Gib diesen Code in der App ein, um deine E-Mail zu bestätigen — du bleibst dabei angemeldet und machst direkt weiter.</p>

  <h2 style="color:#0B0E14;margin:0 0 6px;font-weight:800">Welcome to Cruise Connector</h2>
  <p style="color:#3a4152;margin:0 0 18px;line-height:1.5">Thanks for signing up! Enter this code in the app to confirm your email — you stay signed in and can continue right away.</p>

  <div style="font-size:34px;font-weight:800;letter-spacing:12px;text-align:center;background:#F2F4F8;border-radius:14px;padding:18px 0;color:#0B0E14">{{ .Token }}</div>

  <p style="color:#8A93A6;font-size:13px;margin:16px 0 0;line-height:1.5">Der Code ist 60 Minuten gültig. Du hast dich nicht registriert? Dann ignoriere diese E-Mail einfach.</p>
  <p style="color:#8A93A6;font-size:13px;margin:6px 0 0;line-height:1.5">The code is valid for 60 minutes. Didn't sign up? Just ignore this email.</p>

  <p style="color:#8A93A6;font-size:13px;margin:18px 0 0;line-height:1.5">Falls du die App bereits auf diesem Gerät geöffnet hast, kannst du auch <a href="{{ .ConfirmationURL }}" style="color:#E8552D;font-weight:600">hier direkt bestätigen</a>. · If you already have the app open on this device, you can also <a href="{{ .ConfirmationURL }}" style="color:#E8552D;font-weight:600">confirm directly here</a>.</p>
</div>
```

### Reset Password

Betreff: `Dein Code zum Passwort-Zurücksetzen · Your password reset code`

```html
<div style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;max-width:480px;margin:0 auto;padding:8px">
  <h2 style="color:#0B0E14;margin:0 0 6px;font-weight:800">Passwort zurücksetzen</h2>
  <p style="color:#3a4152;margin:0 0 18px;line-height:1.5">Gib diesen Code in der App ein, um ein neues Passwort zu setzen.</p>

  <h2 style="color:#0B0E14;margin:0 0 6px;font-weight:800">Reset your password</h2>
  <p style="color:#3a4152;margin:0 0 18px;line-height:1.5">Enter this code in the app to set a new password.</p>

  <div style="font-size:34px;font-weight:800;letter-spacing:12px;text-align:center;background:#F2F4F8;border-radius:14px;padding:18px 0;color:#0B0E14">{{ .Token }}</div>

  <p style="color:#8A93A6;font-size:13px;margin:16px 0 0;line-height:1.5">Der Code ist 60 Minuten gültig. Du hast das nicht angefordert? Dann ignoriere diese E-Mail einfach — dein Passwort bleibt unverändert.</p>
  <p style="color:#8A93A6;font-size:13px;margin:6px 0 0;line-height:1.5">The code is valid for 60 minutes. Didn't request this? Just ignore this email — your password stays unchanged.</p>
</div>
```

**Beim Reset fehlt der `{{ .ConfirmationURL }}`-Link mit Absicht** — anders als
beim Signup. Wer ihn antippt, landet zwar angemeldet in der App, hat aber kein
neues Passwort gesetzt und wundert sich beim nächsten Login. Beim Signup ist der
Link dagegen sinnvoll: Dort *ist* das Öffnen bereits die Bestätigung.

## Noch offen

- **Übersetzung der App-Texte** läuft in Wellen (Auth → Rahmen → Cruise →
  Community → Rest → Services). Stand siehe Git-Verlauf dieses Branches.
- **Turn-by-turn-Ansagen:** GraphHopper bekommt `locale: 'de'` fest verdrahtet
  (`supabase/functions/generate-cruise-route-v2/index.ts:737`). Für englische
  Ansagen muss die App ihre Sprache mitschicken und die Function sie
  durchreichen — plus `tts_service.dart:90` (`setLanguage('de-DE')`).
- **Push-Benachrichtigungen** entstehen serverseitig. Dafür braucht es
  `profiles.language` in der DB, das die Edge Functions auswerten.
- **AGB / Datenschutz** liegen extern auf `cruiseconnector.at` (`locale =
  'de-AT'`). Eine englische Fassung ist Website- und Rechtsarbeit — Rechtstexte
  sollten nicht ungeprüft maschinell übersetzt werden.
