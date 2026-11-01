-- Beauty Agenda Premium: cadastro de localização e privacidade (etapa 1)
-- Execute no Supabase SQL Editor uma única vez. Não expõe endereços privados via API pública.
create table if not exists public.business_locations (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 business_name text not null check (char_length(trim(business_name)) between 2 and 120),
 service_mode text not null default 'estabelecimento' check (service_mode in ('estabelecimento','domicilio','ambos')),
 postal_code text not null check (postal_code ~ '^[0-9]{8}$'),
 city text not null,
 state text not null check (state ~ '^[A-Z]{2}$'),
 neighborhood text not null,
 street text,
 street_number text,
 complement text,
 visibility text not null default 'regiao' check (visibility in ('publico','regiao','privado')),
 updated_at timestamptz not null default now()
);
alter table public.business_locations enable row level security;
drop policy if exists "Proprietário lê localização" on public.business_locations;
create policy "Proprietário lê localização" on public.business_locations for select to authenticated using (user_id=(select auth.uid()));
drop policy if exists "Proprietário cadastra localização" on public.business_locations;
create policy "Proprietário cadastra localização" on public.business_locations for insert to authenticated
with check (user_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role in ('profissional','salao')));
drop policy if exists "Proprietário atualiza localização" on public.business_locations;
create policy "Proprietário atualiza localização" on public.business_locations for update to authenticated
using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role in ('profissional','salao')));
-- Acesso público limitado a dados explicitamente seguros, via função SECURITY DEFINER.
-- Não publica CEP, rua/número ou coordenadas de quem optou por privacidade.
create or replace function public.search_business_regions(p_city text default null, p_state text default null)
returns table (business_name text, city text, state text, neighborhood text, service_mode text, visibility text)
language sql stable security definer set search_path = '' as $$
 select b.business_name,b.city,b.state,
 case when b.visibility='privado' then 'Região não divulgada' else b.neighborhood end,
 b.service_mode,b.visibility
 from public.business_locations b
 where (p_city is null or lower(b.city)=lower(p_city))
 and (p_state is null or b.state=upper(p_state))
 order by b.business_name limit 100
$$;
revoke all on function public.search_business_regions(text,text) from public;
grant execute on function public.search_business_regions(text,text) to anon,authenticated;
-- Impede que o próprio usuário altere seu papel para obter privilégios.
create or replace function public.prevent_self_role_change()
returns trigger language plpgsql set search_path = '' as $$
begin
 if new.role is distinct from old.role and (select auth.role()) <> 'service_role' then
  raise exception 'Alteração de tipo de conta não permitida por este acesso';
 end if;
 return new;
end $$;
drop trigger if exists prevent_self_role_change on public.profiles;
create trigger prevent_self_role_change before update on public.profiles for each row execute function public.prevent_self_role_change();
