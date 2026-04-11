-- Add demographic columns to users table for admin analytics
ALTER TABLE users ADD COLUMN language TEXT;
ALTER TABLE users ADD COLUMN gender TEXT;
ALTER TABLE users ADD COLUMN birth_year INTEGER;
