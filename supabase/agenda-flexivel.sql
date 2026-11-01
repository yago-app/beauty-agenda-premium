-- Execute apos agenda-horarios.sql
create table if not exists public.business_day_slots (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references public.business_profiles(user_id) on delete cascade,
 day date not null,
 starts_at time not null,
 ends_at time,
 kind text not null check (kind in ('livre','bloqueado','avulso')),
 check ((kind='avulso' and ends_at is null) or (kind<>'avulso' and ends_at>starts_at))
);
create index if not exists business_day_slots_idx on public.business_day_slots(owner_id,day);
alter table public.business_day_slots enable row level security;
drop policy if exists "owner day slots" on public.business_day_slots;
create policy "owner day slots" on public.business_day_slots for all to authenticated
using (owner_id=auth.uid()) with check (owner_id=auth.uid());

-- Recalcula horarios disponiveis a partir da agenda semanal e das excecoes diarias.
create or replace function public.available_slots(p_business_id uuid,p_service_id uuid,p_day date)
returns table(starts_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare dur integer; op time; cl time; step integer; custom boolean; t timestamptz; fin timestamptz;
begin
 if p_day<(now() at time zone 'America/Sao_Paulo')::date or p_day>(now() at time zone 'America/Sao_Paulo')::date+120 then return; end if;
 select s.duration_minutes into dur from public.business_services s
 join public.business_locations l on l.user_id=s.owner_id
 where s.id=p_service_id and s.owner_id=p_business_id;
 if dur is null then return; end if;
 select a.opens_at,a.closes_at,a.slot_step into op,cl,step from public.business_availability a
 where a.owner_id=p_business_id and a.weekday=extract(dow from p_day)::integer and a.enabled;
 select exists(select 1 from public.business_day_slots d where d.owner_id=p_business_id and d.day=p_day and d.kind in ('livre','avulso')) into custom;
 for t in
  select distinct candidate from (
   select g as candidate from public.business_day_slots d
   cross join lateral generate_series((d.day+d.starts_at) at time zone 'America/Sao_Paulo',
   ((d.day+d.ends_at)-make_interval(mins=>dur)) at time zone 'America/Sao_Paulo',interval '15 minutes') g
   where d.owner_id=p_business_id and d.day=p_day and d.kind='livre'
   union all
   select (d.day+d.starts_at) at time zone 'America/Sao_Paulo'
   from public.business_day_slots d where d.owner_id=p_business_id and d.day=p_day and d.kind='avulso'
   union all
   select g from generate_series((p_day+op) at time zone 'America/Sao_Paulo',
   ((p_day+cl)-make_interval(mins=>dur)) at time zone 'America/Sao_Paulo',
   make_interval(mins=>coalesce(step,30))) g where not custom and op is not null
  ) candidates order by candidate
 loop
  fin:=t+make_interval(mins=>dur);
  if t>now()+interval '15 minutes'
   and not exists(select 1 from public.business_day_slots d where d.owner_id=p_business_id and d.day=p_day and d.kind='bloqueado'
   and tstzrange((d.day+d.starts_at) at time zone 'America/Sao_Paulo',(d.day+d.ends_at) at time zone 'America/Sao_Paulo','[)') && tstzrange(t,fin,'[)'))
   and not exists(select 1 from public.appointments a where a.business_id=p_business_id and a.status='confirmado'
   and tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(t,fin,'[)'))
  then starts_at:=t;return next;end if;
 end loop;
end;$$;
revoke all on function public.available_slots(uuid,uuid,date) from public;
grant execute on function public.available_slots(uuid,uuid,date) to anon,authenticated;
