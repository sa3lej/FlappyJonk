CREATE TABLE IF NOT EXISTS scores (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  score INTEGER NOT NULL,
  beers INTEGER DEFAULT 0,
  ip TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_scores_score ON scores(score DESC);
INSERT INTO scores (name, score, beers) VALUES
  ('LEJ', 62, 0), ('LEJ', 57, 0), ('LEJ', 56, 0), ('LEJ', 53, 0),
  ('LEJ', 52, 0), ('JONK', 52, 0), ('LEJ', 49, 0), ('LEJ', 48, 0),
  ('LEJ', 47, 0), ('LEJ', 45, 0);
