-- Perfil individual do colaborador; execute no SQL Editor do Supabase.
create table if not exists public.collaborator_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null default '',
 bio text not null default '',
 specialties text not null default '',
 photo_url text,
 updated_at timestamptz not null default now()
);
alter table public.collaborator_profiles enable row level security;
drop policy if exists "Colaborador le proprio perfil" on public.collaborator_profiles;
create policy "Colaborador le proprio perfil" on public.collaborator_profiles for select to authenticated using (user_id=auth.uid());
drop policy if exists "Colaborador cria proprio perfil" on public.collaborator_profiles;
create policy "Colaborador cria proprio perfil" on public.collaborator_profiles for insert to authenticated with check (user_id=auth.uid());
drop policy if exists "Colaborador edita proprio perfil" on public.collaborator_profiles;
create policy "Colaborador edita proprio perfil" on public.collaborator_profiles for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
-- Serviços são propostas individuais; publicação e preços do salão permanecem sob controle do responsável.
create table if not exists public.collaborator_services (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 name text not null check (char_length(trim(name)) between 2 and 100),
 duration_minutes integer not null default 30 check (duration_minutes between 5 and 600),
 created_at timestamptz not null default now()
);
create index if not exists collaborator_services_user_idx on public.collaborator_services(user_id);
alter table public.collaborator_services enable row level security;
drop policy if exists "Colaborador gerencia proprios servicos" on public.collaborator_services;
create policy "Colaborador gerencia proprios servicos" on public.collaborator_services for all to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
