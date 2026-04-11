-- Add user_id to blogs for per-user data isolation
ALTER TABLE blogs ADD COLUMN user_id INTEGER;
CREATE INDEX idx_blogs_user ON blogs(user_id);
