-- Privatsphäre: User kann Konto auf privat stellen
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_private boolean NOT NULL DEFAULT false;
