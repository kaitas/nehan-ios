-- Add user_id to logs for per-user data isolation
ALTER TABLE logs ADD COLUMN user_id INTEGER;
CREATE INDEX idx_logs_user_date ON logs(user_id, timestamp);
