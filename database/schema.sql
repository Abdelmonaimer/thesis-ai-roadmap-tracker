CREATE TABLE IF NOT EXISTS thesis_roadmap_progress (
  id SMALLINT PRIMARY KEY CHECK (id = 1),
  items JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS thesis_workspace_records (
  id TEXT PRIMARY KEY,
  record JSONB NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1
);
