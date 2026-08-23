-- 2026-08-23: Die Spaltensperre auf communities.invite_code wird ZURUECKGENOMMEN.
--
-- Sie stammt aus 20260823123000_community_bild_sichtbarkeit_und_code.sql und war
-- als zweite Sicherung gegen das Sammeln von Einladungscodes gedacht. Gemessen
-- kostet sie aber sofort einen Ausfall bei laufenden Nutzern:
--
--   Jede installierte App-Fassung fuehrt invite_code in ihrer Spaltenliste
--   (community_chat_service.dart _communitySelect und _legacyCommunitySelect).
--   Ohne das Spaltenrecht antwortet Postgres mit SQLSTATE 42501
--   "permission denied for table communities" - und zwar fuer die GANZE
--   Abfrage, nicht nur fuer die eine Spalte. Der Rettungspfad _isMissingColumn
--   faengt nur 42703 ab, ein Rechtefehler faellt durch.
--   Folge: Meine Communities, Entdecken und der Chat waeren fuer jeden tot,
--   der die neue App-Fassung noch nicht hat. Die Update-Pflicht ist laut
--   Notiz vom 11.08. noch nicht scharf gestellt.
--   Gemessen betroffen: 29 Nutzer mit Mitgliedschaften, die Entdecken-Liste
--   sehen alle 179.
--
-- Die EIGENTLICHE Absicherung bleibt bestehen und ist die wirksamere:
-- join_community_with_code_v2 prueft is_public. Ein gesammelter Code fuehrt
-- bei einer inzwischen privaten Community nur noch zu einer Beitrittsanfrage,
-- nicht mehr zu einer Mitgliedschaft. Nachgewiesen am Live-Bestand: Fremder
-- mit gueltigem Code auf die private Community ergab Mitgliedschaft 0,
-- Beitrittsanfrage 1.
--
-- Die Sperre kann wieder scharf gestellt werden, sobald min_build_number die
-- alten Fassungen aussperrt.

grant select (invite_code) on public.communities to anon, authenticated;

do $$
declare
  v_spalten int;
begin
  select count(*) into v_spalten
  from information_schema.column_privileges
  where table_schema = 'public' and table_name = 'communities'
    and privilege_type = 'SELECT' and grantee = 'authenticated'
    and column_name = 'invite_code';

  if v_spalten <> 1 then
    raise exception 'invite_code ist fuer authenticated weiterhin gesperrt - die alte App bliebe kaputt.';
  end if;
end $$;

comment on column public.communities.invite_code is
  'Einladungscode. 2026-08-23: bewusst wieder fuer alle Angemeldeten lesbar, '
  'weil die Spaltensperre installierte App-Fassungen mit 42501 lahmgelegt haette. '
  'Der Missbrauch ist stattdessen in join_community_with_code_v2 geschlossen: '
  'bei einer privaten Community fuehrt ein Code nur zu einer Beitrittsanfrage. '
  'Erneut sperren, sobald die Update-Pflicht scharf ist.';
