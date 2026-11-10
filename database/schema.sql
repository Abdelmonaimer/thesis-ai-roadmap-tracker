CREATE TABLE IF NOT EXISTS thesis_roadmap_progress (
  id SMALLINT PRIMARY KEY CHECK (id = 1),
  items JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
