-- Wallnetic Database Schema
-- Users are managed by Supabase Auth automatically

-- Generations table
CREATE TABLE IF NOT EXISTS generations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    prompt TEXT NOT NULL,
    negative_prompt TEXT DEFAULT '',
    model TEXT NOT NULL,
    duration INTEGER NOT NULL DEFAULT 5,
    aspect_ratio TEXT NOT NULL DEFAULT '16:9',
    was_img2vid BOOLEAN NOT NULL DEFAULT FALSE,
    video_url TEXT,
    thumbnail_url TEXT,
    status TEXT NOT NULL DEFAULT 'completed',
    cost DECIMAL(10,4) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Usage tracking table
CREATE TABLE IF NOT EXISTS usage (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    generation_count INTEGER NOT NULL DEFAULT 0,
    total_cost DECIMAL(10,4) DEFAULT 0,
    UNIQUE(user_id, date)
);

-- User preferences (synced settings)
CREATE TABLE IF NOT EXISTS user_preferences (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    default_model TEXT DEFAULT 'kling-standard',
    default_duration INTEGER DEFAULT 5,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_generations_user_id ON generations(user_id);
CREATE INDEX IF NOT EXISTS idx_generations_created_at ON generations(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_user_date ON usage(user_id, date);

-- Row Level Security
ALTER TABLE generations ENABLE ROW LEVEL SECURITY;
ALTER TABLE usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Users can only access their own data
CREATE POLICY "Users can view own generations" ON generations
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own generations" ON generations
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own generations" ON generations
    FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "Users can view own usage" ON usage
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can upsert own usage" ON usage
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own preferences" ON user_preferences
    FOR ALL USING (auth.uid() = user_id);
