-- 2026-08-23, Nachtrag zu 20260823144208_gruppen_einladung_sichtbarkeit.sql.
--
-- Der Supabase-Advisor hat direkt nach dem Einspielen gemeldet:
-- `anon_security_definer_function_executable` fuer invite_to_group und
-- revoke_group_invite. Ursache: Supabase vergibt EXECUTE beim CREATE per
-- Default-Privileg auch an die Rolle `anon`, und ein
-- `revoke ... from public` erwischt genau das NICHT, weil PUBLIC in der
-- Rechteliste gar nicht auftaucht.
--
-- Beide Funktionen brechen fuer nicht angemeldete Aufrufer ohnehin mit
-- „Bitte melde dich an." ab, aber sie haben als /rest/v1/rpc/... offen
-- dagestanden. Nach diesem Nachtrag: 67 statt 69 anon-Meldungen im Advisor.
--
-- Die beiden Lesehilfen ist_zu_gruppe_eingeladen und gruppe_ist_in_der_lobby
-- behalten `anon` mit Absicht: sie stehen in den SELECT-Policies, und
-- Postgres prueft das Ausfuehrungsrecht beim Planen, also auch fuer nicht
-- angemeldete Abfragen auf oeffentliche Gruppen.
revoke all on function public.invite_to_group(uuid, uuid) from public, anon;
grant execute on function public.invite_to_group(uuid, uuid) to authenticated;

revoke all on function public.revoke_group_invite(uuid, uuid) from public, anon;
grant execute on function public.revoke_group_invite(uuid, uuid) to authenticated;
