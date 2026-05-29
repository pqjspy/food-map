-- Nutrition tracker — initial schema.
-- Every user-data table has updated_at + deleted_at (soft delete) so future
-- mobile clients can do delta sync (`updated_at > lastSync`) without a migration.
-- Row Level Security ensures each user can only see their own rows; the anon
-- API key in the client is therefore safe to ship publicly.

-- ---------- updated_at trigger ----------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------- profiles (one row per user) ----------
create table public.profiles (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  sex          text check (sex in ('male','female')),
  age          int  check (age between 10 and 120),
  height_cm    numeric(5,1) check (height_cm between 80 and 250),
  weight_kg    numeric(5,1) check (weight_kg between 25 and 350),
  body_fat_pct numeric(4,1) check (body_fat_pct between 2 and 60),
  activity     text check (activity in ('sedentary','light','active')),
  goal         text check (goal in ('cut','recomp','maintain','bulk')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ---------- weight_log (one row per day per user, soft-deletable) ----------
create table public.weight_log (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  date         date not null,
  weight_kg    numeric(5,1) not null check (weight_kg between 25 and 350),
  body_fat_pct numeric(4,1) check (body_fat_pct between 2 and 60),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create unique index weight_log_user_date_live
  on public.weight_log (user_id, date)
  where deleted_at is null;
create index weight_log_user_updated on public.weight_log (user_id, updated_at);
create trigger weight_log_touch before update on public.weight_log
  for each row execute function public.touch_updated_at();

-- ---------- workouts ----------
create table public.workouts (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  date          date not null,
  type          text not null,
  duration_min  int  not null check (duration_min between 1 and 600),
  intensity     text not null default 'moderate' check (intensity in ('light','moderate','hard')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index workouts_user_date on public.workouts (user_id, date)
  where deleted_at is null;
create index workouts_user_updated on public.workouts (user_id, updated_at);
create trigger workouts_touch before update on public.workouts
  for each row execute function public.touch_updated_at();

-- ---------- meal_entries (one row per logged food) ----------
create table public.meal_entries (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  date            date not null,
  meal            text not null check (meal in ('Breakfast','Lunch','Snack','Dinner')),
  name            text not null,
  brand           text,
  fdc_id          int,
  grams           numeric(7,1) not null check (grams between 0.1 and 5000),
  kcal_per_100g   numeric(6,1) not null,
  c_per_100g      numeric(6,1) not null default 0,
  p_per_100g      numeric(6,1) not null default 0,
  f_per_100g      numeric(6,1) not null default 0,
  source          text not null default 'manual' check (source in ('manual','usda')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create index meal_entries_user_date on public.meal_entries (user_id, date)
  where deleted_at is null;
create index meal_entries_user_updated on public.meal_entries (user_id, updated_at);
create trigger meal_entries_touch before update on public.meal_entries
  for each row execute function public.touch_updated_at();

-- ---------- usda_cache (server-only; Edge Function reads/writes) ----------
create table public.usda_cache (
  query_norm   text primary key,
  results      jsonb not null,
  fetched_at   timestamptz not null default now()
);

-- ---------- Row Level Security ----------
alter table public.profiles     enable row level security;
alter table public.weight_log   enable row level security;
alter table public.workouts     enable row level security;
alter table public.meal_entries enable row level security;
alter table public.usda_cache   enable row level security;

create policy "own profile"  on public.profiles
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own weight"   on public.weight_log
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own workouts" on public.workouts
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own meals"    on public.meal_entries
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- usda_cache has RLS enabled but NO policies — only service-role
-- (Edge Functions) can read or write it. Anon / authenticated clients cannot.
