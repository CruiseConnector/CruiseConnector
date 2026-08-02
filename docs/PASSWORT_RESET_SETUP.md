# Passwort-Reset — Setup (Brevo + Supabase)

Stand: 2026-08-02 · Branch `fix/passwort-reset`

Der Code ist fertig. Was hier steht, sind die **Klicks im Dashboard**, ohne die
keine Mail rausgeht. Ohne Schritt 2 kommt zwar eine Mail an, aber **ohne Code** —
dann bleibt der Nutzer im Code-Feld hängen.

---

## Wie der Flow läuft

```
Login-Seite → „Passwort vergessen?"
   ↓  E-Mail eingeben
resetPasswordForEmail()        → Supabase → Brevo-SMTP → Mail mit 6-stelligem Code
   ↓  Code aus der Mail eintippen
verifyOTP(type: recovery)      → Recovery-Session
   ↓  neues Passwort + Wiederholung
updateUser(password: …)        → fertig, direkt angemeldet in der App
```

Bewusst **kein Magic-Link**: derselbe Code-Weg wie bei der Signup-Bestätigung.
Ein Link-Rückweg müsste über Deep-Links laufen und kollidiert auf Android mit
dem OAuth-Handler in `lib/main.dart` — genau deshalb wurde das Onboarding schon
auf Code umgestellt.

**Zweiter Einstieg:** Einstellungen → Konto & Privatsphäre → „Passwort ändern"
(war vorher ein toter Menüpunkt). Dort: aktuelles Passwort → neues Passwort.
Reine Google-/Apple-Konten sehen stattdessen „Passwort festlegen" (ohne Abfrage
des alten Passworts, weil es keins gibt). Der Link „Passwort vergessen?" führt
von dort in denselben Code-Flow.

---

## Schritt 1 — Brevo als SMTP in Supabase eintragen

Supabase Dashboard → **Project Settings → Authentication → SMTP Settings** →
*Enable Custom SMTP*.

| Feld | Wert |
|---|---|
| Host | `smtp-relay.brevo.com` |
| Port | `587` |
| Username | dein Brevo-**SMTP-Login** (Form `9xxxxx@smtp-brevo.com`) |
| Password | der Brevo-**SMTP-Key** |
| Sender email | Absender-Adresse einer in Brevo **verifizierten Domain** |
| Sender name | `Cruise Connector` |

Brevo-Werte findest du unter **Brevo → SMTP & API → Reiter „SMTP"**. Der
SMTP-Key ist *nicht* derselbe wie der REST-API-Key (`xkeysib-…`).

> **Wichtig:** Die Absender-Domain muss in Brevo verifiziert sein (SPF/DKIM
> gesetzt). Sonst landen die Mails im Spam oder werden abgewiesen — und der
> Nutzer sieht nur „kein Code angekommen".

Ohne Custom-SMTP nutzt Supabase seinen eingebauten Versand mit **~3 Mails pro
Stunde für das ganze Projekt** — zum Testen zu zweit reicht das schon nicht.

---

## Schritt 2 — Mail-Template auf Code umstellen (der kritische Teil)

Supabase Dashboard → **Authentication → Email Templates → „Reset Password"**.

Das Standard-Template enthält nur `{{ .ConfirmationURL }}` (Link). Die App
erwartet einen **6-stelligen Code** → `{{ .Token }}` muss rein:

```html
<h2>Passwort zurücksetzen</h2>
<p>Dein Code für Cruise Connector:</p>
<p style="font-size:32px;font-weight:bold;letter-spacing:8px;">{{ .Token }}</p>
<p>Gib den Code in der App ein. Er ist 1 Stunde gültig.</p>
<p>Du hast das nicht angefordert? Dann ignoriere diese Mail einfach — dein
Passwort bleibt unverändert.</p>
```

Den Link (`{{ .ConfirmationURL }}`) kannst du drin lassen oder rauswerfen — die
App braucht ihn nicht. **Empfehlung: rauswerfen**, sonst tippen manche Nutzer den
Link an, landen in der App und sind zwar angemeldet, haben aber kein neues
Passwort gesetzt.

Gültigkeit des Codes: **Authentication → Providers → Email → Email OTP
Expiration** (Default 3600 s = 1 Stunde).

---

## Schritt 3 — Rate-Limit prüfen

Supabase Dashboard → **Authentication → Rate Limits** → *Emails per hour*.

Default ist niedrig. Mit Brevo-SMTP kann der Wert hoch (z. B. 100/h). Die App
fängt das Limit ab und zeigt „Zu viele E-Mails in kurzer Zeit" statt eines
englischen GoTrue-Fehlers — und sperrt den „Erneut senden"-Button für 3 Minuten.

---

## Testen

1. App starten, Login-Seite → **„Passwort vergessen?"**
2. Eigene Adresse eintragen → *Code senden*
3. Mail kommt (auch **Spam-Ordner** prüfen) → 6 Ziffern eintippen
   → springt automatisch weiter, sobald die 6. Ziffer steht
4. Neues Passwort 2× → *Passwort speichern* → „Weiter zur App"
5. Gegenprobe: ausloggen, mit dem **neuen** Passwort anmelden

**Wenn keine Mail kommt:** Brevo → *Transaktional → Logs* zeigt jede Zustellung
mit Status. Steht dort nichts, kam die Anfrage nie bei Brevo an → SMTP-Zugang in
Supabase falsch. Steht dort „blocked/bounced" → Absender-Domain nicht verifiziert.

**Wenn die Mail kommt, aber ohne Ziffern:** Schritt 2 fehlt (`{{ .Token }}`).

---

## Betroffene Dateien

| Was | Wo |
|---|---|
| Service-Methoden (senden, Code prüfen, Passwort setzen) | `lib/data/services/auth_service.dart` |
| Reset-Seite (3 Schritte) | `lib/presentation/pages/forgot_password_page.dart` |
| Passwort ändern (Einstellungen) | `lib/presentation/pages/change_password_page.dart` |
| „Passwort vergessen?"-Button | `lib/presentation/pages/login_page.dart` |
| Menüpunkt verdrahtet | `lib/presentation/pages/settings_page.dart` |
| Passwort-/E-Mail-Regeln + Tests | `lib/core/input_limits.dart`, `test/core/input_limits_password_test.dart` |
