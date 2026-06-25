-- Foto an einer (gespeicherten) Route persistieren — damit man in der
-- Uebersicht/gespeicherten Routen ein Foto nachtraeglich hinzufuegen kann und es
-- dort bleibt (zusaetzlich zum Foto der gefahrenen Drive-Session). Additiv +
-- nullable -> kein Risiko fuer bestehende Zeilen. Die vorhandene UPDATE-Policy
-- "User kann eigene Routen updaten" deckt das Setzen/Aendern bereits ab.
alter table public.routes add column if not exists photo_url text;
