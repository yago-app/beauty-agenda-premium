-- Beauty Agenda Premium — etapa 3: agendamentos
-- Execute após perfis-publicos.sql
create extension if not exists btree_gist;
create table if not exists public.appointments (
 id uuid primary key default gen_random_uuid(),
 client_id uuid not null references public.profiles(id),
 business_id uuid not null references public.business_profiles(user_id),
 service_id uuid not null references public.business_services(id),
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 status text not null default 'pendente' check(status in ('pendente','confirmado','recusado','cancelado','concluido')),
 notes text not null default '' check(char_length(notes)<=500),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint appointment_duration_valid check(ends_at>starts_at and ends_at<=starts_at+interval '24 hours'),
 constraint appointment_no_overlap exclude using gist(business_id with =,tstzrange(starts_at,ends_at,'[)') with &&) where(status='confirmado')
);
create index if not exists appointments_client_idx on public.appointments(client_id,starts_at desc);
create index if not exists appointments_business_idx on public.appointments(business_id,starts_at desc);
alter table public.appointments enable row level security;
drop policy if exists "Cliente e dono veem agendamentos" on public.appointments;
create policy "Cliente e dono veem agendamentos" on public.appointments for select to authenticated
using(client_id=(select auth.uid()) or business_id=(select auth.uid()));
-- Toda alteração de estado passa por RPC para evitar falsificação.
create or replace function public.request_appointment(p_business_id uuid,p_service_id uuid,p_starts_at timestamptz,p_notes text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare v_client uuid:=auth.uid();v_role text;v_duration integer;v_id uuid;
begin
 if v_client is null then raise exception 'Faça login para agendar.'; end if;
 select role into v_role from public.profiles where id=v_client;
 if v_role<>'cliente' then raise exception 'Entre com uma conta de cliente para agendar.'; end if;
 if p_starts_at<=now()+interval '15 minutes' or p_starts_at>now()+interval '120 days' then raise exception 'Escolha uma data futura dentro dos próximos 120 dias.'; end if;
 if p_notes is null or char_length(p_notes)>500 then raise exception 'Observação inválida.'; end if;
 select s.duration_minutes into v_duration from public.business_services s
 join public.business_profiles bp on bp.user_id=s.owner_id
 join public.business_locations bl on bl.user_id=bp.user_id
 where s.id=p_service_id and s.owner_id=p_business_id;
 if v_duration is null then raise exception 'Serviço indisponível.'; end if;
 if exists(select 1 from public.appointments a where a.business_id=p_business_id and a.status='confirmado' and tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(p_starts_at,p_starts_at+make_interval(mins=>v_duration),'[)')) then raise exception 'Horário já reservado. Escolha outro.'; end if;
 insert into public.appointments(client_id,business_id,service_id,starts_at,ends_at,notes)
 values(v_client,p_business_id,p_service_id,p_starts_at,p_starts_at+make_interval(mins=>v_duration),p_notes) returning id into v_id;
 return v_id;
end;$$;
create or replace function public.change_appointment_status(p_appointment_id uuid,p_status text)
returns void language plpgsql security definer set search_path='' as $$
declare a public.appointments%rowtype;v_user uuid:=auth.uid();
begin
 if v_user is null then raise exception 'Faça login.'; end if;
 select * into a from public.appointments where id=p_appointment_id for update;
 if not found then raise exception 'Agendamento não encontrado.'; end if;
 if p_status='cancelado' and a.client_id=v_user and a.status in ('pendente','confirmado') and a.starts_at>now() then null;
 elsif a.business_id=v_user and ((a.status='pendente' and p_status in ('confirmado','recusado')) or (a.status='confirmado' and p_status='concluido' and a.ends_at<=now())) then null;
 else raise exception 'Transição de status não permitida.'; end if;
 update public.appointments set status=p_status,updated_at=now() where id=p_appointment_id;
end;$$;
-- Dados de serviços e clientes exibidos somente aos participantes.
create or replace function public.my_appointments()
returns table(id uuid,client_id uuid,business_id uuid,service_name text,client_name text,business_name text,starts_at timestamptz,ends_at timestamptz,status text,notes text)
language sql stable security definer set search_path='' as $$
 select a.id,a.client_id,a.business_id,s.name,p.full_name,bp.display_name,a.starts_at,a.ends_at,a.status,a.notes
 from public.appointments a join public.business_services s on s.id=a.service_id
 join public.profiles p on p.id=a.client_id join public.business_profiles bp on bp.user_id=a.business_id
 where auth.uid() in (a.client_id,a.business_id)
 order by a.starts_at desc limit 200;
$$;
revoke all on function public.request_appointment(uuid,uuid,timestamptz,text) from public;
revoke all on function public.change_appointment_status(uuid,text) from public;
revoke all on function public.my_appointments() from public;
grant execute on function public.request_appointment(uuid,uuid,timestamptz,text) to authenticated;
grant execute on function public.change_appointment_status(uuid,text) to authenticated;
grant execute on function public.my_appointments() to authenticated;

-- Serviços selecionáveis pelo cliente (somente estabelecimentos com localização)
create or replace function public.bookable_services(p_business_id uuid)
returns table(id uuid,name text,description text,price_cents integer,duration_minutes integer)
language sql stable security definer set search_path='' as $$
 select s.id,s.name,s.description,s.price_cents,s.duration_minutes
 from public.business_services s
 join public.business_profiles bp on bp.user_id=s.owner_id
 join public.business_locations bl on bl.user_id=bp.user_id
 where s.owner_id=p_business_id order by s.name limit 100;
$$;
revoke all on function public.bookable_services(uuid) from public;
grant execute on function public.bookable_services(uuid) to anon,authenticated;
