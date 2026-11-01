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
