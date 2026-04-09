CREATE TABLE IF NOT EXISTS logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp TEXT NOT NULL,
  type TEXT NOT NULL CHECK(type IN ('location', 'sleep', 'memo')),
  latitude REAL,
  longitude REAL,
  place_name TEXT,
  payload TEXT,
  synced_from TEXT DEFAULT 'ios',
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_logs_type ON logs(type);
CREATE INDEX IF NOT EXISTS idx_logs_date ON logs(date(timestamp));
