-- Fehlende Spalten für Route-Speicherung
ALTER TABLE routes ADD COLUMN IF NOT EXISTS route_type text;
ALTER TABLE routes ADD COLUMN IF NOT EXISTS duration_seconds float;
