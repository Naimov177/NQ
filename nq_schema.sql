-- =====================================================================
-- NQ (Next Quest): схема базы данных для Supabase (PostgreSQL)
-- Запускается один раз в SQL Editor. Повторный запуск безопасен.
-- Главное правило: у каждой записи есть владелец (user_id), и каждый
-- пользователь видит и меняет только свои записи (Row Level Security).
-- =====================================================================
begin;

-- ---------- служебные функции ----------
create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end $$;

-- ---------- профили: создаются сами при регистрации ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, nullif(split_part(coalesce(new.email, ''), '@', 1), ''))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

insert into public.profiles (id, display_name)
select u.id, nullif(split_part(coalesce(u.email, ''), '@', 1), '')
from auth.users u on conflict (id) do nothing;

-- ---------- люди (общий список для поля «Ответственный») ----------
create table if not exists public.people (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 40),
  created_at timestamptz not null default now()
);
create unique index if not exists people_user_name_uq on public.people (user_id, lower(name));

-- ---------- проекты ----------
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 200),
  block text not null default 'alif' check (block in ('alif', 'personal')),
  notes jsonb not null default '[]'::jsonb check (jsonb_typeof(notes) = 'array'),
  comments jsonb not null default '[]'::jsonb check (jsonb_typeof(comments) = 'array'),
  advice_done boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id)
);
create index if not exists projects_user_idx on public.projects (user_id, sort_order, created_at);

-- ---------- задачи ----------
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  project_id uuid,
  title text not null check (length(btrim(title)) between 1 and 500),
  description text not null default '' check (length(description) <= 20000),
  assignees text[] not null default array['Я'],
  created_on date not null default current_date,
  due date,
  status text not null default 'Новая'
    check (status in ('Новая', 'В работе', 'На проверке', 'Завершена', 'Отменена')),
  priority text not null default 'Средний'
    check (priority in ('Низкий', 'Средний', 'Высокий', 'Критический')),
  focus boolean not null default false,
  repeat text check (repeat is null or repeat = 'daily'),
  start_on date,
  end_on date,
  done_on date,
  moves integer not null default 0 check (moves >= 0),
  notes jsonb not null default '[]'::jsonb check (jsonb_typeof(notes) = 'array'),
  comments jsonb not null default '[]'::jsonb check (jsonb_typeof(comments) = 'array'),
  links jsonb not null default '[]'::jsonb check (jsonb_typeof(links) = 'array'),
  files jsonb not null default '[]'::jsonb check (jsonb_typeof(files) = 'array'),
  advice_done boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- задача может ссылаться только на проект того же владельца
  constraint tasks_project_fk foreign key (project_id, user_id)
    references public.projects (id, user_id) on delete cascade
);
create index if not exists tasks_user_project_idx on public.tasks (user_id, project_id);
create index if not exists tasks_user_due_idx on public.tasks (user_id, due);
create index if not exists tasks_user_status_idx on public.tasks (user_id, status);

-- ---------- входящие ----------
create table if not exists public.inbox_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  text text not null check (length(btrim(text)) between 1 and 5000),
  created_at timestamptz not null default now()
);
create index if not exists inbox_user_idx on public.inbox_items (user_id, created_at desc);

-- ---------- идеи ----------
create table if not exists public.ideas (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  text text not null check (length(btrim(text)) between 1 and 500),
  body text not null default '' check (length(body) <= 50000),
  status text not null default 'В копилке' check (status in ('В копилке', 'Беру в работу', 'Отброшена')),
  comments jsonb not null default '[]'::jsonb check (jsonb_typeof(comments) = 'array'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists ideas_user_idx on public.ideas (user_id, created_at desc);

-- ---------- ежедневные задачи и отметки выполнения ----------
create table if not exists public.habits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 200),
  time_of_day text not null default '09:00' check (time_of_day ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (id, user_id)
);
create index if not exists habits_user_idx on public.habits (user_id, sort_order, created_at);

create table if not exists public.habit_logs (
  habit_id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  day date not null,
  primary key (habit_id, day),
  constraint habit_logs_habit_fk foreign key (habit_id, user_id)
    references public.habits (id, user_id) on delete cascade
);
create index if not exists habit_logs_user_day_idx on public.habit_logs (user_id, day);

-- ---------- прогресс «Саморазвития» и прочее состояние (одна строка на человека) ----------
create table if not exists public.user_state (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  dev jsonb not null default '{}'::jsonb check (jsonb_typeof(dev) = 'object' and pg_column_size(dev) < 500000),
  settings jsonb not null default '{}'::jsonb check (jsonb_typeof(settings) = 'object' and pg_column_size(settings) < 50000),
  updated_at timestamptz not null default now()
);

-- ---------- автоматическое обновление updated_at ----------
drop trigger if exists projects_updated_at on public.projects;
create trigger projects_updated_at before update on public.projects for each row execute function public.set_updated_at();
drop trigger if exists tasks_updated_at on public.tasks;
create trigger tasks_updated_at before update on public.tasks for each row execute function public.set_updated_at();
drop trigger if exists ideas_updated_at on public.ideas;
create trigger ideas_updated_at before update on public.ideas for each row execute function public.set_updated_at();
drop trigger if exists user_state_updated_at on public.user_state;
create trigger user_state_updated_at before update on public.user_state for each row execute function public.set_updated_at();

-- ---------- защита данных: каждый видит и меняет только своё ----------
do $$
declare t text;
begin
  foreach t in array array['people', 'projects', 'tasks', 'inbox_items', 'ideas', 'habits', 'habit_logs', 'user_state'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "only own rows" on public.%I', t);
    execute format(
      'create policy "only own rows" on public.%I for all to authenticated '
      'using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
  end loop;
end $$;

alter table public.profiles enable row level security;
drop policy if exists "read own profile" on public.profiles;
create policy "read own profile" on public.profiles for select to authenticated using (id = (select auth.uid()));
drop policy if exists "update own profile" on public.profiles;
create policy "update own profile" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- ---------- права доступа: только вошедшим пользователям, анонимным ничего ----------
revoke all on public.profiles, public.people, public.projects, public.tasks, public.inbox_items,
  public.ideas, public.habits, public.habit_logs, public.user_state from anon;
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.people, public.projects, public.tasks, public.inbox_items,
  public.ideas, public.habits, public.habit_logs, public.user_state to authenticated;

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.set_updated_at() from public, anon, authenticated;

-- ---------- хранилище файлов (вложения к задачам), у каждого своя папка ----------
insert into storage.buckets (id, name, public, file_size_limit)
values ('attachments', 'attachments', false, 10485760)
on conflict (id) do update set public = false, file_size_limit = 10485760;

drop policy if exists "attachments: read own folder" on storage.objects;
create policy "attachments: read own folder" on storage.objects for select to authenticated
  using (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "attachments: upload to own folder" on storage.objects;
create policy "attachments: upload to own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "attachments: update own folder" on storage.objects;
create policy "attachments: update own folder" on storage.objects for update to authenticated
  using (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "attachments: delete own folder" on storage.objects;
create policy "attachments: delete own folder" on storage.objects for delete to authenticated
  using (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);

commit;
