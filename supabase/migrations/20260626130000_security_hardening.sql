-- 2026-06-26 (vucko): Security-Härtung — geschlossene, LIVE-verifizierte Lücken
-- aus dem Pentest. Bereits per MCP angewandt; diese Datei spiegelt den Stand
-- (idempotent re-applybar).

-- 1) Backup-Tabellen waren OHNE RLS in public => via Anon-Key lesbar.
--    RLS aktivieren (keine Policy = deny-all für anon/authenticated; service_role
--    umgeht weiterhin => Restore möglich). [bewiesen: anon las 3 Zeilen je Tabelle]
alter table if exists public.route_pool_backup_20260609          enable row level security;
alter table if exists public.route_pool_coverage_backup_20260609 enable row level security;
alter table if exists public.route_pool_coverage_targets_bak_20260613 enable row level security;

-- 2) Route-Pool-Tabellen hatten ALL using(true)/check(true) für {anon,authenticated}
--    => JEDER ohne Login konnte INSERT/UPDATE/DELETE (Pool vergiften/löschen).
--    App ist voll auth-gated (kein Anon/Gast-Login) => Write auf authenticated
--    beschränken bricht nichts; Edge/Cron schreiben als service_role (umgeht RLS).
--    [bewiesen: anon INSERT danach => 42501 row-level security, HTTP 401]
alter policy "Route pool candidates sind schreibbar" on public.route_pool_candidates to authenticated;
alter policy "Route pool coverage ist schreibbar"    on public.route_pool_coverage   to authenticated;
alter policy "Route seed jobs sind schreibbar"       on public.route_seed_jobs        to authenticated;

-- 3) 3 Views liefen als SECURITY DEFINER => umgingen RLS der Grundtabellen.
--    security_invoker=on lässt sie die RLS des abfragenden Nutzers respektieren.
--    Grundtabellen erlauben authenticated-SELECT => App (auth-gated) unbeeinträchtigt.
alter view if exists public.active_construction_reports set (security_invoker = on);
alter view if exists public.pool_demand_aggregate       set (security_invoker = on);
alter view if exists public.route_pool_coverage_audit   set (security_invoker = on);

-- 4) Public-Buckets erlaubten ANON-LISTING => Enumeration aller User-UIDs + Pfade.
--    Public-URL-Reads umgehen die SELECT-RLS (bewiesen: avatar.jpg lädt ohne Auth)
--    => Listing/auth-Read auf authenticated beschränken bricht die Anzeige nicht.
--    [bewiesen danach: anon-LIST => 0 Objekte, Public-URL => HTTP 200]
alter policy "avatars_public_read"    on storage.objects to authenticated;
alter policy "banners_public_read"    on storage.objects to authenticated;
alter policy "car_images_public_read" on storage.objects to authenticated;
alter policy "ride-photos read"       on storage.objects to authenticated;
