-- Beauty Agenda Premium: ciclo de atendimento e registro de recebimento
-- Requer supabase/gestao-equipe.sql aplicado primeiro.
-- Nesta etapa, somente o proprietario autenticado pode executar transicoes.
alter table public.appointments add column if not exists attendance_state text not null default 'nao_iniciado';
alter table public.appointments drop constraint if exists appointments_attendance_state_check;
alter table public.appointments add constraint appointments_attendance_state_check check (attendance_state in ('nao_iniciado','em_atendimento','aguardando_pagamento','finalizado'));
alter table public.appointments add column if not exists attendance_started_at timestamptz;
alter table public.appointments add column if not exists attendance_finished_at timestamptz;

create table if not exists public.appointment_payments (
 id uuid primary key default gen_random_uuid(),
 appointment_id uuid not null unique references public.appointments(id) on delete restrict,
 business_id uuid not null references public.business_profiles(user_id),
 amount_cents integer not null check(amount_cents>0),
 payment_method text not null check(payment_method in ('pix','dinheiro','credito','debito','outro')),
 confirmed_by uuid not null references auth.users(id),
 confirmed_at timestamptz not null default now()
);
create index if not exists appointment_payments_business_idx on public.appointment_payments(business_id,confirmed_at desc);
alter table public.appointment_payments enable row level security;
drop policy if exists "Dono consulta recebimentos" on public.appointment_payments;
create policy "Dono consulta recebimentos" on public.appointment_payments for select to authenticated using(business_id=(select auth.uid()));

create or replace function public.owner_attendance_action(p_appointment_id uuid,p_action text,p_amount_cents integer default null,p_payment_method text default null)
returns void language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid();v public.appointments%rowtype;
begin
 if v_actor is null then raise exception 'Faca login.';end if;
 select * into v from public.appointments where id=p_appointment_id for update;
 if not found or v.business_id is distinct from v_actor then raise exception 'Atendimento nao encontrado ou acesso negado.';end if;
 if p_action='iniciar' then
   if v.status<>'confirmado' or v.attendance_state<>'nao_iniciado' then raise exception 'Somente agendamentos confirmados e nao iniciados podem comecar.';end if;
   update public.appointments set attendance_state='em_atendimento',attendance_started_at=now(),updated_at=now() where id=v.id;
 elsif p_action='encerrar_servico' then
   if v.attendance_state<>'em_atendimento' then raise exception 'O servico precisa estar em andamento.';end if;
   update public.appointments set attendance_state='aguardando_pagamento',attendance_finished_at=now(),updated_at=now() where id=v.id;
 elsif p_action='confirmar_pagamento' then
   if v.attendance_state<>'aguardando_pagamento' or v.status<>'confirmado' then raise exception 'O atendimento nao esta aguardando pagamento.';end if;
   if p_amount_cents is null or p_amount_cents<=0 or p_payment_method not in ('pix','dinheiro','credito','debito','outro') or p_payment_method is null then raise exception 'Informe valor e forma de pagamento validos.';end if;
   insert into public.appointment_payments(appointment_id,business_id,amount_cents,payment_method,confirmed_by)
   values(v.id,v_actor,p_amount_cents,p_payment_method);
   update public.appointments set attendance_state='finalizado',status='concluido',updated_at=now() where id=v.id;
 else
   raise exception 'Acao desconhecida.';
 end if;
end;$$;
revoke all on function public.owner_attendance_action(uuid,text,integer,text) from public;
grant execute on function public.owner_attendance_action(uuid,text,integer,text) to authenticated;
