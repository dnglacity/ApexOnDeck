-- Migration: add format_slots column to game_rosters
-- Stores format-template slot assignments: keys are "$sectionIdx-$positionIdx",
-- values are player UUIDs.  Allows the format position assignments to persist
-- when a saved roster is closed and re-opened.

ALTER TABLE public.game_rosters
  ADD COLUMN IF NOT EXISTS format_slots jsonb NOT NULL DEFAULT '{}'::jsonb;
