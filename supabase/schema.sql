-- Beauty Agenda Premium — estrutura inicial segura de perfis
-- Execute no SQL Editor do projeto Supabase antes de ativar o cadastro no site.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null default 'cliente' check (role in ('cliente','profissional','salao')),
  whatsapp text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint whatsapp_format check (whatsapp is null or whatsapp ~ '^55[1-9][0-9]{9,10}$')
);

alter table public.profiles enable row level security;

drop policy if exists "Usuário lê seu próprio perfil" on public.profiles;
create policy "Usuário lê seu próprio perfil" on public.profiles
for select to authenticated using ((select auth.uid()) = id);

drop policy if exists "Usuário atualiza seu próprio perfil" on public.profiles;
create policy "Usuário atualiza seu próprio perfil" on public.profiles
for update to authenticated using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

-- Novos perfis são criados automaticamente pelo servidor, não pelo navegador.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, role, whatsapp)
  values (
    new.id,
    nullif(left(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), 150), ''),
    case when new.raw_user_meta_data ->> 'role' in ('cliente','profissional','salao')
      then new.raw_user_meta_data ->> 'role' else 'cliente' end,
    case when new.raw_user_meta_data ->> 'role' = 'salao'
      and (new.raw_user_meta_data ->> 'whatsapp') ~ '^55[1-9][0-9]{9,10}$'
      then new.raw_user_meta_data ->> 'whatsapp' else null end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users for each row execute function public.handle_new_user();

-- Atenção: whatsapp fica privado nesta etapa.
-- Para perfis públicos, criar uma visão/tabela separada com consentimento do proprietário.
