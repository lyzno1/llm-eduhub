-- 创建 profiles 表（如果不存在）
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID REFERENCES auth.users(id) PRIMARY KEY,
  full_name TEXT,
  username TEXT UNIQUE,
  avatar_url TEXT,
  updated_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- 启用行级安全
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 创建策略，允许用户读取所有资料（如果不存在）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'profiles' 
    AND policyname = '允许所有用户查看所有资料'
  ) THEN
    EXECUTE 'CREATE POLICY "允许所有用户查看所有资料" ON public.profiles FOR SELECT USING (true)';
  END IF;
END
$$;

-- 创建策略，只允许用户更新自己的资料（如果不存在）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'profiles' 
    AND policyname = '允许用户更新自己的资料'
  ) THEN
    EXECUTE 'CREATE POLICY "允许用户更新自己的资料" ON public.profiles FOR UPDATE USING (auth.uid() = id)';
  END IF;
END
$$;

-- 创建策略，只允许用户插入自己的资料（如果不存在）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'profiles' 
    AND policyname = '允许用户插入自己的资料'
  ) THEN
    EXECUTE 'CREATE POLICY "允许用户插入自己的资料" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id)';
  END IF;
END
$$;

-- 创建函数，在用户注册时自动创建资料
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, username, avatar_url, created_at, updated_at)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'full_name',
    CONCAT('user_', SUBSTRING(CAST(NEW.id AS TEXT), 1, 8)), -- 生成临时用户名
    NEW.raw_user_meta_data->>'avatar_url',
    NEW.created_at,
    NEW.created_at
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 删除现有触发器（如果存在）
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- 创建触发器，在用户创建时调用函数
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
  
-- 更新现有记录，确保所有记录都有 username 值
UPDATE public.profiles
SET username = CONCAT('user_', SUBSTRING(CAST(id AS TEXT), 1, 8))
WHERE username IS NULL OR username = '';
