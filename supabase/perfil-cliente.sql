-- Etapa 2: campos privados do perfil do cliente
alter table public.profiles
  add column if not exists phone text,
  add column if not exists birth_date date,
  add column if not exists avatar_url text;

alter table public.profiles
  drop constraint if exists profiles_phone_format;
alter table public.profiles
  add constraint profiles_phone_format check (phone is null or phone ~ '^55[1-9][0-9]{9,10}$');

-- As regras RLS já existentes limitam a leitura e atualização ao próprio titular.
-- A foto será armazenada no Storage, com leitura autenticada e escrita somente do proprietário.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-photos', 'profile-photos', false, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false, file_size_limit=2097152, allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists "Foto própria: visualizar" on storage.objects;
create policy "Foto própria: visualizar" on storage.objects for select to authenticated
using (bucket_id='profile-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "Foto própria: enviar" on storage.objects;
create policy "Foto própria: enviar" on storage.objects for insert to authenticated
with check (bucket_id='profile-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "Foto própria: atualizar" on storage.objects;
create policy "Foto própria: atualizar" on storage.objects for update to authenticated
using (bucket_id='profile-photos' and (storage.foldername(name))[1]=(select auth.uid())::text)
with check (bucket_id='profile-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "Foto própria: excluir" on storage.objects;
create policy "Foto própria: excluir" on storage.objects for delete to authenticated
using (bucket_id='profile-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);
