# Task für Claude: Implementierung der Melde- und Blockier-Funktion (UGC)

Hallo Claude, 

deine Aufgabe ist es, die Melde- und Blockier-Funktion für User Generated Content (UGC) vollumfänglich in Flutter und Supabase zu implementieren. Ohne diese Funktion wird die App von Apple und Google abgelehnt.

Bitte arbeite die folgenden Anforderungen Schritt für Schritt ab:

## 1. Supabase Backend (Datenbank & RLS)
* Erstelle eine Tabelle `user_blocks` (z.B. mit `blocker_id`, `blocked_id`).
* Erstelle eine Tabelle `content_reports` (z.B. mit `reporter_id`, `reported_user_id`, `post_id`, `reason`, `status`).
* Setze sichere RLS Policies auf (User können nur eigene Blocks und Reports anlegen/lesen).
* **Feed & Entdecken-Filter:** Passe unsere bestehenden Queries/RPCs an. Wenn User A den User B blockiert hat, dürfen sie gegenseitig keine Posts mehr im Feed oder in der Entdecken-Seite sehen.

## 2. Flutter Frontend (UI)
* **3-Punkte-Menü:** Integriere an jedem Post und auf den Profilen anderer User ein Menü mit der Option "Beitrag melden / Benutzer melden" sowie "Benutzer blockieren".
* **Gruppen-Ansicht:** Blockierte Benutzer sollen in Gruppen ausgegraut dargestellt werden (mit Hinweis, dass sie blockiert wurden). Auch sie dürfen deinen Content in der Gruppe nicht sehen.
* **Neuer Menüpunkt im Profil:** Erweitere den Drawer (`profile_page.dart`) unter "Einstellungen" um den Punkt "Blockierte Nutzer".
* **Blocked Users Page:** Erstelle eine neue UI-Seite, die alle blockierten Nutzer auflistet, mit der Möglichkeit, diese wieder zu entblocken.
* Das UI muss sich direkt updaten, sobald ein User blockiert wird (Posts verschwinden sofort aus der aktuellen Ansicht).

## 3. Admin & Moderation (Für uns Entwickler)
* Lass dir ein skalierbares System einfallen, mit dem wir als Devs eingehende Meldungen (`content_reports`) einsehen können.
* **Bann- und Lösch-Logik:** Erstelle Supabase RPCs oder Edge Functions, mit denen wir:
  1. Einzelne Posts löschen können.
  2. Einen Account löschen oder bannen können (`is_banned` Flag).
* **Trigger:** Wenn ein User gebannt wird, lösche oder verstecke automatisch alle seine Posts.
* **Review-Möglichkeit:** Baue entweder eine versteckte Web-Admin-View in Flutter oder liefere uns klare SQL-Skripte/Edge Functions, wie wir diese Reports abarbeiten können.

Bitte aktualisiere die entsprechenden Flutter-Dateien (`lib/...`) sowie die `SETUP_COMPLETE.sql` für die Datenbank-Änderungen.