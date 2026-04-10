CREATE TABLE IF NOT EXISTS blogs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL,
  date TEXT NOT NULL,
  title TEXT,
  body TEXT NOT NULL,
  cover_url TEXT,
  is_draft INTEGER DEFAULT 0,
  published_at TEXT DEFAULT (datetime('now')),
  created_at TEXT DEFAULT (datetime('now')),
  UNIQUE(username, date)
);
