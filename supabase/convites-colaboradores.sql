-- Execute apos gestao-equipe.sql. Convite seguro por e-mail autenticado.
-- CPF nao e usado como credencial nem armazenado nesta primeira etapa.
alter table public.business_team add column if not exists invite_email text;
alter table public.business_team add column if not exists linked_user_id uuid references auth.users(id);
alter table public.business_team add column if not exists invitation_status text not null default 'sem_convite';
alter table public.business_team drop constraint if exists business_team_invitation_status_check;
alter table public.business_team add constraint business_team_invitation_status_check check(invitation_status in ('sem_convite','pendente','aceito','revogado'));
create unique index if not exists team_unique_link_per_owner on public.business_team(owner_id,linked_user_id) where linked_user_id is not null;
create unique index if not exists team_unique_invite_per_owner on public.business_team(owner_id,lower(invite_email)) where invite_email is not null and invitation_status in ('pendente','aceito');

create or replace function public.invite_team_member(p_member_id uuid,p_email text)
returns void language plpgsql security definer set search_path='' as $$
declare v_owner uuid:=auth.uid();v_email text:=lower(trim(p_email));
begin
 if v_owner is null then raise exception 'Faca login.';end if;
 if v_email is null or char_length(v_email)>254 or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'E-mail invalido.';end if;
 update public.business_team set invite_email=v_email,invitation_status='pendente',linked_user_id=null
 where id=p_member_id and owner_id=v_owner and active and invitation_status<>'aceito';
 if not found then raise exception 'Colaborador indisponivel ou convite ja aceito.';end if;
end;$$;
revoke all on function public.invite_team_member(uuid,text) from public;
grant execute on function public.invite_team_member(uuid,text) to authenticated;

create or replace function public.my_team_invitations()
returns table(member_id uuid,salon_id uuid,salon_name text,member_name text)
language sql stable security definer set search_path='' as $$
 select t.id,t.owner_id,coalesce(bp.business_name,'Salao'),t.full_name
 from public.business_team t join public.business_profiles bp on bp.user_id=t.owner_id
 where t.invitation_status='pendente' and t.active
 and lower(t.invite_email)=lower((select email from auth.users where id=auth.uid()))
 and (select email_confirmed_at from auth.users where id=auth.uid()) is not null;
$$;
revoke all on function public.my_team_invitations() from public;
grant execute on function public.my_team_invitations() to authenticated;

create or replace function public.accept_team_invitation(p_member_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_email text;
begin
 if v_user is null then raise exception 'Faca login.';end if;
 select lower(email) into v_email from auth.users where id=v_user and email_confirmed_at is not null;
 if v_email is null then raise exception 'Confirme seu e-mail primeiro.';end if;
 update public.business_team set linked_user_id=v_user,invitation_status='aceito'
 where id=p_member_id and active and invitation_status='pendente' and lower(invite_email)=v_email;
 if not found then raise exception 'Convite nao encontrado para este e-mail.';end if;
end;$$;
revoke all on function public.accept_team_invitation(uuid) from public;
grant execute on function public.accept_team_invitation(uuid) to authenticated;

create or replace function public.my_team_memberships()
returns table(member_id uuid,salon_id uuid,salon_name text,member_name text)
language sql stable security definer set search_path='' as $$
 select t.id,t.owner_id,coalesce(bp.business_name,'Salao'),t.full_name
 from public.business_team t join public.business_profiles bp on bp.user_id=t.owner_id
 where t.linked_user_id=auth.uid() and t.invitation_status='aceito' and t.active;
$$;
revoke all on function public.my_team_memberships() from public;
grant execute on function public.my_team_memberships() to authenticated;
