-- 2026-07-26: Sicherheits-Hotfix. anon und authenticated hatten TRUNCATE auf
-- road_incidents und road_incident_votes. TRUNCATE umgeht Row Level Security
-- VOLLSTAENDIG — ein einziger eingeloggter Nutzer haette damit saemtliche
-- Verkehrsmeldungen aller Nutzer loeschen koennen. DELETE war ebenfalls
-- gewaehrt (durch fehlende DELETE-Policy zwar faktisch blockiert, aber die
-- Absicherung haengt dann allein an RLS statt zusaetzlich am Recht selbst).
-- REFERENCES/TRIGGER braucht ein Client ohnehin nie.
-- SELECT/INSERT/UPDATE bleiben unveraendert, damit die App weiterlaeuft.
revoke truncate, delete, references, trigger on public.road_incidents from anon, authenticated;
revoke truncate, delete, references, trigger on public.road_incident_votes from anon, authenticated;

-- anon darf gar nichts schreiben: die INSERT-Policy verlangt
-- reported_by = auth.uid(), was fuer anon NULL ist — das Recht selbst war
-- trotzdem gesetzt. Weg damit (Defense in Depth).
revoke insert, update on public.road_incidents from anon;
revoke insert, update on public.road_incident_votes from anon;;
