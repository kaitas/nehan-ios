-- Per-user authentication: users table
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE,
  email TEXT,
  email_verified_at TEXT,
  api_key_hash TEXT NOT NULL,
  device_id TEXT UNIQUE NOT NULL,
  tier INTEGER DEFAULT 0,
  tos_accepted_at TEXT,
  tos_version TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_users_api_key ON users(api_key_hash);
CREATE INDEX IF NOT EXISTS idx_users_device ON users(device_id);
