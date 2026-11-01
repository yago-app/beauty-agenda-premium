-- Beauty Agenda Premium — etapa 2: perfis de profissionais e salões
-- Execute no SQL Editor após localizacao-privacidade.sql
create table if not exists public.business_profiles (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 display_name text not null check (char_length(trim(display_name)) between 2 and 120),
 bio text not null default '' check (char_length(bio)<=2000),
 specialties text not null default '' check (char_length(specialties)<=500),
 whatsapp text check (whatsapp is null or whatsapp ~ '^55[1-9][0-9]{9,10}$'),
 instagram text not null default '' check (char_length(instagram)<=120),
 opening_hours text not null default '' check (char_length(opening_hours)<=1000),
 updated_at timestamptz not null default now()
);
alter table public.business_profiles enable row level security;
drop policy if exists "Dono lê perfil comercial" on public.business_profiles;
create policy "Dono lê perfil comercial" on public.business_profiles for select to authenticated using(user_id=(select auth.uid()));
drop policy if exists "Dono cadastra perfil comercial" on public.business_profiles;
create policy "Dono cadastra perfil comercial" on public.business_profiles for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role in ('profissional','salao')));
drop policy if exists "Dono edita perfil comercial" on public.business_profiles;
create policy "Dono edita perfil comercial" on public.business_profiles for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role in ('profissional','salao')));
create table if not exists public.business_services (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references public.business_profiles(user_id) on delete cascade,
 name text not null check(char_length(trim(name)) between 2 and 100),
 description text not null default '' check(char_length(description)<=500),
 price_cents integer not null check(price_cents>=0 and price_cents<=100000000),
 duration_minutes integer not null check(duration_minutes between 5 and 1440),
 created_at timestamptz not null default now()
);
create index if not exists business_services_owner_idx on public.business_services(owner_id);
alter table public.business_services enable row level security;
drop policy if exists "Dono gerencia serviços select" on public.business_services;
create policy "Dono gerencia serviços select" on public.business_services for select to authenticated using(owner_id=(select auth.uid()));
drop policy if exists "Dono gerencia serviços insert" on public.business_services;
create policy "Dono gerencia serviços insert" on public.business_services for insert to authenticated with check(owner_id=(select auth.uid()));
drop policy if exists "Dono gerencia serviços update" on public.business_services;
create policy "Dono gerencia serviços update" on public.business_services for update to authenticated using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
drop policy if exists "Dono gerencia serviços delete" on public.business_services;
create policy "Dono gerencia serviços delete" on public.business_services for delete to authenticated using(owner_id=(select auth.uid()));
-- Arquivos comerciais são públicos por opção do dono; escrita limitada à pasta do usuário.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('business-media','business-media',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists "Dono envia mídia comercial" on storage.objects;
create policy "Dono envia mídia comercial" on storage.objects for insert to authenticated
with check(bucket_id='business-media' and (storage.foldername(name))[1]=(select auth.uid())::text and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role in ('profissional','salao')));
drop policy if exists "Dono atualiza mídia comercial" on storage.objects;
create policy "Dono atualiza mídia comercial" on storage.objects for update to authenticated
using(bucket_id='business-media' and (storage.foldername(name))[1]=(select auth.uid())::text)
with check(bucket_id='business-media' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "Dono remove mídia comercial" on storage.objects;
create policy "Dono remove mídia comercial" on storage.objects for delete to authenticated
using(bucket_id='business-media' and (storage.foldername(name))[1]=(select auth.uid())::text);
