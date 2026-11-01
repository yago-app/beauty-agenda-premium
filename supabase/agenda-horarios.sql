-- Beauty Agenda Premium — agenda semanal e disponibilidade
-- Execute depois de agendamentos.sql
create table if not exists public.business_availability (
 owner_id uuid not null references public.business_profiles(user_id) on delete cascade,
 weekday integer not null check(weekday between 0 and 6),
 enabled boolean not null default false,
 opens_at time not null default '09:00',
 closes_at time not null default '18:00',
 slot_step integer not null default 30 check(slot_step in (15,30,60)),
 primary key(owner_id,weekday),
 check(opens_at<closes_at)
);
alter table public.business_availability enable row level security;
drop policy if exists "Owner manages availability" on public.business_availability;
create policy "Owner manages availability" on public.business_availability for all to authenticated
using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
create or replace function public.available_slots(p_business_id uuid,p_service_id uuid,p_day date)
returns table(starts_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare v_duration int;v_open time;v_close time;v_step int;v_start timestamptz;v_end timestamptz;v_day date;
begin
 if p_day<((now() at time zone 'America/Sao_Paulo')::date) or p_day>((now() at time zone 'America/Sao_Paulo')::date+120) then return; end if;
 select s.duration_minutes into v_duration from public.business_services s
 join public.business_locations l on l.user_id=s.owner_id
 where s.id=p_service_id and s.owner_id=p_business_id;
 if v_duration is null then return; end if;
 select a.opens_at,a.closes_at,a.slot_step into v_open,v_close,v_step
 from public.business_availability a where a.owner_id=p_business_id and a.weekday=extract(dow from p_day)::integer and a.enabled;
 if v_open is null then return; end if;
 for v_start in select generate_series((p_day+v_open) at time zone 'America/Sao_Paulo',
 ((p_day+v_close)-make_interval(mins=>v_duration)) at time zone 'America/Sao_Paulo',
 make_interval(mins=>v_step)) loop
   v_end:=v_start+make_interval(mins=>v_duration);
   if v_start>now()+interval '15 minutes'
     and not exists(select 1 from public.appointments a where a.business_id=p_business_id and a.status='confirmado'
     and tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(v_start,v_end,'[)'))
   then starts_at:=v_start;return next;end if;
 end loop;
end;$$;
-- Valida horários no servidor: não confiar no calendário do navegador
create or replace function public.request_appointment(p_business_id uuid,p_service_id uuid,p_starts_at timestamptz,p_notes text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare v_client uuid:=auth.uid();v_role text;v_duration int;v_id uuid;v_day date;
begin
 if v_client is null then raise exception 'Faça login para agendar.'; end if;
 select role into v_role from public.profiles where id=v_client;
 if v_role<>'cliente' then raise exception 'Entre com uma conta de cliente.'; end if;
 if p_starts_at<=now()+interval '15 minutes' or p_starts_at>now()+interval '120 days' then raise exception 'Data fora do período permitido.'; end if;
 if p_notes is null or char_length(p_notes)>500 then raise exception 'Observação inválida.'; end if;
 select duration_minutes into v_duration from public.business_services where id=p_service_id and owner_id=p_business_id;
 if v_duration is null then raise exception 'Serviço indisponível.'; end if;
 v_day:=(p_starts_at at time zone 'America/Sao_Paulo')::date;
 if not exists(select 1 from public.available_slots(p_business_id,p_service_id,v_day) s where s.starts_at=p_starts_at) then
 raise exception 'Horário indisponível. Escolha outro horário da agenda.'; end if;
 insert into public.appointments(client_id,business_id,service_id,starts_at,ends_at,notes)
 values(v_client,p_business_id,p_service_id,p_starts_at,p_starts_at+make_interval(mins=>v_duration),p_notes) returning id into v_id;
 return v_id;
end;$$;
-- A confirmação também valida a agenda atual e a ausência de conflitos.
create or replace function public.change_appointment_status(p_appointment_id uuid,p_status text)
returns void language plpgsql security definer set search_path='' as $$
declare a public.appointments%rowtype;v_user uuid:=auth.uid();v_day date;
begin
 if v_user is null then raise exception 'Faça login.'; end if;
 select * into a from public.appointments where id=p_appointment_id for update;
 if not found then raise exception 'Agendamento não encontrado.'; end if;
 if p_status='cancelado' and a.client_id=v_user and a.status in ('pendente','confirmado') and a.starts_at>now() then null;
 elsif a.business_id=v_user and ((a.status='pendente' and p_status in ('confirmado','recusado')) or (a.status='confirmado' and p_status='concluido' and a.ends_at<=now())) then
   if p_status='confirmado' then
     v_day:=(a.starts_at at time zone 'America/Sao_Paulo')::date;
     if not exists(select 1 from public.available_slots(a.business_id,a.service_id,v_day) s where s.starts_at=a.starts_at) then
       raise exception 'Horário indisponível ou fora da agenda.'; end if;
   end if;
 else raise exception 'Transição não permitida.'; end if;
 update public.appointments set status=p_status,updated_at=now() where id=p_appointment_id;
end;$$;
revoke all on function public.available_slots(uuid,uuid,date) from public;
grant execute on function public.available_slots(uuid,uuid,date) to anon,authenticated;
