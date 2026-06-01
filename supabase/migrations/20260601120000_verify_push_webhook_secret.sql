-- Push-Webhook-Secret gegen den Vault prüfen, ohne dass das Secret die DB
-- verlässt. 2026-06-01 (vucko): Vorher verglich die send-push Edge-Function das
-- x-push-secret gegen ihr Function-Env PUSH_WEBHOOK_SECRET — das konnte vom
-- Vault-Wert (den der Trigger schickt) abweichen (→ 401, kein Push). Jetzt gibt
-- es nur EINE Source-of-Truth (Vault), die send-push via dieser Funktion prüft.
create or replace function public.verify_push_webhook_secret(candidate text)
returns boolean
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_secret text;
begin
  if candidate is null or length(candidate) = 0 then
    return false;
  end if;
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'push_webhook_secret'
  limit 1;
  if v_secret is null then
    return false;
  end if;
  return candidate = v_secret;
end;
$$;

-- Nur die Edge-Function (service_role) darf prüfen — kein Brute-Force durch
-- normale Clients.
revoke all on function public.verify_push_webhook_secret(text) from public;
revoke all on function public.verify_push_webhook_secret(text) from anon;
revoke all on function public.verify_push_webhook_secret(text) from authenticated;
grant execute on function public.verify_push_webhook_secret(text) to service_role;
