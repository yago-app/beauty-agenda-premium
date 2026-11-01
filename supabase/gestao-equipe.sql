-- Beauty Agenda Premium — equipe e operacoes do salao
-- Execute apos agenda-horarios.sql e agendamentos.sql
-- Valores dos planos: gratis 0, pro 3, plus 10, premium ilimitado.
create table if not exists public.business_subscriptions (
 owner_id uuid primary key references public.business_profiles(user_id) on delete cascade,
 plan_code text not null default 'gratis' check(plan_code in ('gratis','pro','plus','premium')),
 updated_at timestamptz not null default now()
);
alter table public.business_subscriptions enable row level security;
drop policy if exists "Assinatura visivel ao dono" on public.business_subscriptions;
create policy "Assinatura visivel ao dono" on public.business_subscriptions for select to authenticated using(owner_id=(select auth.uid()));
-- Atribuicao de planos pagos e exclusiva do backend administrativo futuro.
insert into public.business_subscriptions(owner_id,plan_code)
select user_id,'gratis' from public.business_profiles on conflict(owner_id) do nothing;

create table if not exists public.business_team (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references public.business_profiles(user_id) on delete cascade,
 full_name text not null check(char_length(trim(full_name)) between 2 and 120),
 specialty text not null default '' check(char_length(specialty)<=160),
 active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(id,owner_id)
);
create index if not exists business_team_owner_idx on public.business_team(owner_id,active);
alter table public.business_team enable row level security;
drop policy if exists "Equipe visivel ao dono" on public.business_team;
create policy "Equipe visivel ao dono" on public.business_team for select to authenticated using(owner_id=(select auth.uid()));

create or replace function public.manage_team_member(p_name text,p_specialty text default '',p_member_id uuid default null,p_active boolean default true)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_owner uuid:=auth.uid();v_plan text;v_limit int;v_count int;v_id uuid;v_role text;
begin
 if v_owner is null then raise exception 'Faça login.';end if;
 select role into v_role from public.profiles where id=v_owner;
 if v_role not in ('salao','profissional') or not exists(select 1 from public.business_profiles where user_id=v_owner) then raise exception 'Acesso negado.';end if;
 if p_name is null or char_length(trim(p_name)) not between 2 and 120 or char_length(coalesce(p_specialty,''))>160 then raise exception 'Dados do colaborador invalidos.';end if;
 -- Serializa operacoes de cadastro do mesmo proprietario.
 perform 1 from public.business_profiles where user_id=v_owner for update;
 select plan_code into v_plan from public.business_subscriptions where owner_id=v_owner;
 v_limit:=case coalesce(v_plan,'gratis') when 'pro' then 3 when 'plus' then 10 when 'premium' then 2147483647 else 0 end;
 select count(*) into v_count from public.business_team where owner_id=v_owner and active;
 if p_member_id is null then
   if v_count>=v_limit then raise exception 'Limite de colaboradores do plano atingido.';end if;
   insert into public.business_team(owner_id,full_name,specialty,active) values(v_owner,trim(p_name),coalesce(p_specialty,''),true) returning id into v_id;
 else
   if not exists(select 1 from public.business_team where id=p_member_id and owner_id=v_owner) then raise exception 'Colaborador nao encontrado.';end if;
   if p_active and exists(select 1 from public.business_team where id=p_member_id and owner_id=v_owner and not active) and v_count>=v_limit then raise exception 'Limite de colaboradores do plano atingido.';end if;
   update public.business_team set full_name=trim(p_name),specialty=coalesce(p_specialty,''),active=p_active where id=p_member_id and owner_id=v_owner;
   v_id:=p_member_id;
 end if;
 return v_id;
end;$$;
revoke all on function public.manage_team_member(text,text,uuid,boolean) from public;
grant execute on function public.manage_team_member(text,text,uuid,boolean) to authenticated;

alter table public.appointments add column if not exists team_member_id uuid;
alter table public.appointments add column if not exists service_price_cents integer;
alter table public.appointments add constraint appointment_team_owner_fk foreign key(team_member_id,business_id) references public.business_team(id,owner_id);
-- Preco registrado no atendimento, sem assumir que foi pago.
update public.appointments a set service_price_cents=s.price_cents from public.business_services s where a.service_id=s.id and a.service_price_cents is null;
create or replace function public.capture_appointment_price()
returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='INSERT' then
   select price_cents into new.service_price_cents from public.business_services where id=new.service_id and owner_id=new.business_id;
 end if;
 return new;
end;$$;
drop trigger if exists capture_appointment_price on public.appointments;
create trigger capture_appointment_price before insert on public.appointments for each row execute function public.capture_appointment_price();

create table if not exists public.appointment_audit (
 id bigint generated always as identity primary key,
 appointment_id uuid not null references public.appointments(id) on delete cascade,
 business_id uuid not null,
 actor_id uuid,
 action text not null,
 old_status text,
 new_status text,
 old_starts_at timestamptz,
 new_starts_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists appointment_audit_business_idx on public.appointment_audit(business_id,created_at desc);
alter table public.appointment_audit enable row level security;
drop policy if exists "Auditoria visivel ao dono" on public.appointment_audit;
create policy "Auditoria visivel ao dono" on public.appointment_audit for select to authenticated using(business_id=(select auth.uid()));
create or replace function public.audit_appointment()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
 insert into public.appointment_audit(appointment_id,business_id,actor_id,action,new_status,new_starts_at) values(new.id,new.business_id,auth.uid(),'criado',new.status,new.starts_at);
 elsif old.status is distinct from new.status or old.starts_at is distinct from new.starts_at or old.team_member_id is distinct from new.team_member_id then
 insert into public.appointment_audit(appointment_id,business_id,actor_id,action,old_status,new_status,old_starts_at,new_starts_at)
 values(new.id,new.business_id,auth.uid(),case when old.starts_at is distinct from new.starts_at then 'horario_alterado' when old.team_member_id is distinct from new.team_member_id then 'colaborador_alterado' else 'status_alterado' end,old.status,new.status,old.starts_at,new.starts_at);
 end if;
 return new;
end;$$;
drop trigger if exists audit_appointment on public.appointments;
create trigger audit_appointment after insert or update on public.appointments for each row execute function public.audit_appointment();

create or replace function public.assign_appointment_member(p_appointment_id uuid,p_member_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_owner uuid:=auth.uid();v_appointment public.appointments%rowtype;
begin
 select * into v_appointment from public.appointments where id=p_appointment_id for update;
 if not found or v_appointment.business_id is distinct from v_owner then raise exception 'Agendamento nao encontrado.';end if;
 if v_appointment.status in ('cancelado','recusado') then raise exception 'Agendamento inativo.';end if;
 if p_member_id is not null and not exists(select 1 from public.business_team where id=p_member_id and owner_id=v_owner and active) then raise exception 'Colaborador invalido.';end if;
 update public.appointments set team_member_id=p_member_id,updated_at=now() where id=p_appointment_id;
end;$$;
revoke all on function public.assign_appointment_member(uuid,uuid) from public;
grant execute on function public.assign_appointment_member(uuid,uuid) to authenticated;

-- Troca atomica de horarios: bloqueia ambos os registros e valida disponibilidade.
create or replace function public.swap_appointment_times(p_first uuid,p_second uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_owner uuid:=auth.uid();a public.appointments%rowtype;b public.appointments%rowtype;v_a_start timestamptz;v_a_end timestamptz;v_b_start timestamptz;v_b_end timestamptz;
begin
 if p_first=p_second then raise exception 'Selecione dois agendamentos diferentes.';end if;
 -- Trava deterministica para evitar deadlock.
 perform 1 from public.appointments where id in (p_first,p_second) order by id for update;
 select * into a from public.appointments where id=p_first;
 select * into b from public.appointments where id=p_second;
 if a.id is null or b.id is null or a.business_id is distinct from v_owner or b.business_id is distinct from v_owner then raise exception 'Agendamentos nao encontrados.';end if;
 if a.status not in ('pendente','confirmado') or b.status not in ('pendente','confirmado') then raise exception 'So e possivel trocar agendamentos ativos.';end if;
 if a.starts_at<=now() or b.starts_at<=now() then raise exception 'Nao e possivel trocar atendimentos passados.';end if;
 v_a_start:=b.starts_at;v_a_end:=b.starts_at+(a.ends_at-a.starts_at);
 v_b_start:=a.starts_at;v_b_end:=a.starts_at+(b.ends_at-b.starts_at);
 if v_a_start<=now()+interval '15 minutes' or v_b_start<=now()+interval '15 minutes' then raise exception 'Horario muito proximo.';end if;
 -- A troca entre duracoes diferentes pode invadir horarios de terceiros.
 if exists(select 1 from public.appointments x where x.business_id=v_owner and x.id not in (a.id,b.id) and x.status='confirmado'
 and (tstzrange(x.starts_at,x.ends_at,'[)') && tstzrange(v_a_start,v_a_end,'[)') or tstzrange(x.starts_at,x.ends_at,'[)') && tstzrange(v_b_start,v_b_end,'[)'))) then raise exception 'Conflito com outro atendimento.';end if;
 -- Restricao antiga de exclusao impede atualizar um de cada vez. Usamos um update unico,
 -- com a restricao convertida para DEFERRABLE abaixo.
 set constraints appointment_no_overlap deferred;
 update public.appointments set starts_at=case when id=a.id then v_a_start else v_b_start end,
 ends_at=case when id=a.id then v_a_end else v_b_end end,updated_at=now() where id in(a.id,b.id);
 set constraints appointment_no_overlap immediate;
end;$$;
-- Necessario para a troca atomica de dois horarios confirmados.
alter table public.appointments drop constraint if exists appointment_no_overlap;
alter table public.appointments add constraint appointment_no_overlap exclude using gist(business_id with =,tstzrange(starts_at,ends_at,'[)') with &&) where(status='confirmado') deferrable initially immediate;
revoke all on function public.swap_appointment_times(uuid,uuid) from public;
grant execute on function public.swap_appointment_times(uuid,uuid) to authenticated;

create or replace function public.owner_team_appointments()
returns table(id uuid,client_name text,team_member_id uuid,service_name text,service_price_cents integer,starts_at timestamptz,ends_at timestamptz,status text)
language sql stable security definer set search_path='' as $$
select a.id,p.full_name,a.team_member_id,s.name,a.service_price_cents,a.starts_at,a.ends_at,a.status
from public.appointments a join public.profiles p on p.id=a.client_id join public.business_services s on s.id=a.service_id
where a.business_id=auth.uid() order by a.starts_at desc limit 500;
$$;
revoke all on function public.owner_team_appointments() from public;
grant execute on function public.owner_team_appointments() to authenticated;
