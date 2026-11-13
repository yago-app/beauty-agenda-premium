-- Presenca da equipe: executar apos convites-colaboradores.sql
create table if not exists public.team_presence (
 member_id uuid primary key references public.business_team(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 last_seen_at timestamptz not null default now(),
 device_type text not null default 'desktop' check(device_type in ('desktop','celular','tablet'))
);
alter table public.team_presence enable row level security;
drop policy if exists "Dono consulta presenca da equipe" on public.team_presence;
create policy "Dono consulta presenca da equipe" on public.team_presence for select to authenticated using (
 exists(select 1 from public.business_team t where t.id=member_id and t.owner_id=auth.uid())
);
create or replace function public.touch_team_presence(p_member_id uuid,p_device text default 'desktop')
returns void language plpgsql security definer set search_path='' as $$
begin
 if p_device not in ('desktop','celular','tablet') then raise exception 'Dispositivo invalido'; end if;
 if not exists(select 1 from public.business_team where id=p_member_id and linked_user_id=auth.uid() and invitation_status='aceito' and active) then raise exception 'Sem acesso a este colaborador'; end if;
 insert into public.team_presence(member_id,user_id,last_seen_at,device_type)
 values(p_member_id,auth.uid(),now(),p_device)
 on conflict(member_id) do update set last_seen_at=now(),device_type=excluded.device_type,user_id=excluded.user_id;
end;$$;
revoke all on function public.touch_team_presence(uuid,text) from public;
grant execute on function public.touch_team_presence(uuid,text) to authenticated;
