-- Beauty Agenda Premium: leitura pública segura dos perfis comerciais
-- Execute após perfis-comerciais.sql e localizacao-privacidade.sql
-- Nunca retorna endereço exato, CEP, telefone privado ou dados de autenticação.
create or replace function public.public_business_directory(p_city text default null,p_state text default null,p_business_id uuid default null)
returns table(business_id uuid,display_name text,bio text,specialties text,whatsapp text,instagram text,opening_hours text,city text,state text,neighborhood text,service_mode text,visibility text)
language sql stable security definer set search_path='' as $$
 select bp.user_id,bp.display_name,bp.bio,bp.specialties,bp.whatsapp,bp.instagram,bp.opening_hours,
 bl.city,bl.state,case when bl.visibility='privado' then null else bl.neighborhood end,
 bl.service_mode,bl.visibility
 from public.business_profiles bp
 join public.business_locations bl on bl.user_id=bp.user_id
 join public.profiles p on p.id=bp.user_id
 where p.role in ('profissional','salao')
 and (p_business_id is null or bp.user_id=p_business_id)
 and (p_city is null or lower(trim(bl.city))=lower(trim(p_city)))
 and (p_state is null or upper(bl.state)=upper(trim(p_state)))
 order by bp.display_name limit 100;
$$;
revoke all on function public.public_business_directory(text,text,uuid) from public;
grant execute on function public.public_business_directory(text,text,uuid) to anon,authenticated;
create or replace function public.public_business_services(p_business_id uuid)
returns table(name text,description text,price_cents integer,duration_minutes integer)
language sql stable security definer set search_path='' as $$
 select s.name,s.description,s.price_cents,s.duration_minutes
 from public.business_services s
 join public.business_profiles bp on bp.user_id=s.owner_id
 join public.profiles p on p.id=bp.user_id
 join public.business_locations bl on bl.user_id=bp.user_id
 where s.owner_id=p_business_id and p.role in ('profissional','salao')
 order by s.name limit 100;
$$;
revoke all on function public.public_business_services(uuid) from public;
grant execute on function public.public_business_services(uuid) to anon,authenticated;
