-- 2026-06-26 (vucko): Security-Härtung Runde 2 — aus dem Pentest-Loop.
-- Bereits LIVE per MCP angewandt; diese Datei spiegelt den Stand (idempotent).

-- 1) Admin-Moderations-View v_admin_reports_inbox war an anon/authenticated
--    ge-grantet (security_invoker => RLS gatet Zeilen, aber ein Melder konnte
--    via der View die E-Mail des Gemeldeten sehen). App nutzt die View nicht;
--    Admin-Tooling läuft als service_role (behält Zugriff).
revoke all on public.v_admin_reports_inbox from anon, authenticated;

-- 2) Pool-Tabellen sind client-seedbar (authenticated INSERT/UPDATE nötig —
--    route_pool_service.dart), aber der Client DELETEt NIE. Restriktive
--    DELETE-Deny-Policy verhindert Pool-Wipe durch einen eingeloggten
--    Angreifer, ohne die bestehende INSERT/UPDATE-Policy zu verändern.
--    Cron/Edge schreiben als service_role => umgehen RLS => Rotation unberührt.
do $$ begin
  if not exists (select 1 from pg_policy where polname='rpc_block_auth_delete') then
    create policy "rpc_block_auth_delete" on public.route_pool_candidates
      as restrictive for delete to authenticated using (false);
  end if;
  if not exists (select 1 from pg_policy where polname='rpcov_block_auth_delete') then
    create policy "rpcov_block_auth_delete" on public.route_pool_coverage
      as restrictive for delete to authenticated using (false);
  end if;
  if not exists (select 1 from pg_policy where polname='rsj_block_auth_delete') then
    create policy "rsj_block_auth_delete" on public.route_seed_jobs
      as restrictive for delete to authenticated using (false);
  end if;
end $$;

-- 3) profiles.email-Spalten-Leak: anon/authenticated dürfen die E-Mail-Spalte
--    NICHT lesen (jeder eingeloggte User konnte fremde E-Mails abgreifen; anon
--    sogar ohne Login direkt via REST). Client liest die Spalte nicht mehr
--    (ab Build 1.0.4+50 alle profiles:* Embeds ohne email). Signup nutzt
--    upsert() OHNE select() => liest email nie zurück. Edge/Trigger laufen als
--    service_role/owner => unberührt.
--    HINWEIS: Dieser revoke wird ERST nach Auslieferung von +50 auf alle
--    Testgeräte scharf geschaltet (sonst brechen Community-/Gruppen-Embeds des
--    +49-Builds). Hier dokumentiert; Anwendung in 20260626150000.
-- revoke select(email) on public.profiles from anon, authenticated;
