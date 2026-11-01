-- Avaliações verificadas após agendamento concluído
create table if not exists public.business_reviews(
 appointment_id uuid primary key references public.appointments(id) on delete cascade,
 business_id uuid not null references public.business_profiles(user_id),
 client_id uuid not null references public.profiles(id),
 rating integer not null check(rating between 1 and 5),
 comment text not null default '' check(char_length(comment)<=1000),
 created_at timestamptz not null default now()
);
create index if not exists business_reviews_business_idx on public.business_reviews(business_id,created_at desc);
alter table public.business_reviews enable row level security;
drop policy if exists "Avaliacoes publicas" on public.business_reviews;
create policy "Avaliacoes publicas" on public.business_reviews for select to anon,authenticated using(true);
-- Inserção só pela função: impede avaliar atendimento alheio ou não concluído.
create or replace function public.submit_business_review(p_appointment_id uuid,p_rating integer,p_comment text default '')
returns void language plpgsql security definer set search_path='' as $$
declare v_a public.appointments%rowtype;
begin
 if auth.uid() is null then raise exception 'Faça login para avaliar.'; end if;
 if p_rating is null or p_rating<1 or p_rating>5 then raise exception 'Selecione de 1 a 5 estrelas.'; end if;
 if p_comment is null or char_length(p_comment)>1000 then raise exception 'Comentário inválido.'; end if;
 select * into v_a from public.appointments where id=p_appointment_id;
 if not found or v_a.client_id<>auth.uid() then raise exception 'Atendimento não encontrado.'; end if;
 if v_a.status<>'concluido' or v_a.ends_at>now() then raise exception 'Só é possível avaliar atendimentos concluídos.'; end if;
 insert into public.business_reviews(appointment_id,business_id,client_id,rating,comment)
 values(v_a.id,v_a.business_id,v_a.client_id,p_rating,trim(p_comment));
exception when unique_violation then raise exception 'Você já avaliou este atendimento.';
end;$$;
create or replace function public.public_business_reviews(p_business_id uuid)
returns table(rating integer,comment text,created_at timestamptz,client_name text)
language sql stable security definer set search_path='' as $$
 select r.rating,r.comment,r.created_at,coalesce(nullif(split_part(p.full_name,' ',1),''),'Cliente')
 from public.business_reviews r join public.profiles p on p.id=r.client_id
 join public.business_profiles bp on bp.user_id=r.business_id
 join public.business_locations bl on bl.user_id=bp.user_id
 where r.business_id=p_business_id order by r.created_at desc limit 100;
$$;
create or replace function public.my_business_review_ids()
returns table(appointment_id uuid) language sql stable security definer set search_path='' as $$
 select r.appointment_id from public.business_reviews r where r.client_id=auth.uid();
$$;
revoke all on function public.submit_business_review(uuid,integer,text) from public;
revoke all on function public.public_business_reviews(uuid) from public;
revoke all on function public.my_business_review_ids() from public;
grant execute on function public.submit_business_review(uuid,integer,text) to authenticated;
grant execute on function public.public_business_reviews(uuid) to anon,authenticated;
grant execute on function public.my_business_review_ids() to authenticated;
