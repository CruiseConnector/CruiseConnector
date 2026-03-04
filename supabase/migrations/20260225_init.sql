-- Tabelle für deine Cruise-Routen
CREATE TABLE IF NOT EXISTS routes (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at timestamp with time zone DEFAULT now(),
  user_id uuid REFERENCES auth.users(id),
  name text,
  style text, -- Hier kommen 'Kurvenjagd', 'Sport Mode', etc. rein
  distance_target int, -- Deine Vorgabe (z.B. 50 km)
  distance_actual float, -- Was Mapbox tatsächlich berechnet hat
  geometry jsonb -- Das wichtigste: Hier landet die Linie für die Karte
);