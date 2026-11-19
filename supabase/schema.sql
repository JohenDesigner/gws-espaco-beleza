-- Agenda GWS Espaço Beleza · projeto Supabase próprio gws-espaco-beleza (kqonnkaongmsjwdpeuoo)
-- Uma profissional só, dois locais, UMA agenda:
--   * nenhum atendimento se sobrepõe (independente do local);
--   * entre atendimentos em locais diferentes há no mínimo 60 min (deslocamento).
--     Feito com a coluna "folga" (período ±30 min) + exclusion (local <> local, folga && folga).
-- Ter–sáb 08:00–18:00 (fecha dom e seg), passos de 30 min.

create extension if not exists btree_gist with schema extensions;

create table public.locais (
  id smallint primary key,
  slug text not null unique,
  nome text not null,
  endereco text not null,
  ativo boolean not null default true
);

create table public.servicos (
  id smallint primary key,
  slug text not null unique,
  nome text not null,
  duracao_min int not null check (duracao_min between 15 and 480 and duracao_min % 15 = 0),
  ativo boolean not null default true,
  ordem int not null default 0
);

create table public.agendamentos (
  id uuid primary key default gen_random_uuid(),
  servico_id smallint not null references public.servicos(id),
  local_id smallint not null references public.locais(id),
  periodo tstzrange not null,
  folga tstzrange not null,  -- periodo com 30 min a mais de cada lado (preenchida por agendar)
  nome text not null check (char_length(btrim(nome)) between 2 and 80),
  telefone text not null check (telefone ~ '^[0-9]{10,13}$'),
  obs text check (obs is null or char_length(obs) <= 500),
  status text not null default 'confirmado' check (status in ('confirmado','cancelado')),
  criado_em timestamptz not null default now(),
  constraint sem_sobreposicao exclude using gist (periodo with &&) where (status = 'confirmado'),
  constraint deslocamento exclude using gist (local_id with <>, folga with &&) where (status = 'confirmado')
);
create index agendamentos_periodo_idx on public.agendamentos using gist (periodo);

create table public.bloqueios (
  id uuid primary key default gen_random_uuid(),
  periodo tstzrange not null,
  motivo text check (motivo is null or char_length(motivo) <= 120),
  criado_em timestamptz not null default now()
);
create index bloqueios_periodo_idx on public.bloqueios using gist (periodo);

create table public.admins (email text primary key);
comment on table public.admins is 'Somente leitura interna via is_admin(); sem acesso pela API de propósito.';

insert into public.locais (id, slug, nome, endereco) values
  (1, 'miguel-yunes', 'Av. Miguel Yunes', 'Av. Miguel Yunes · Usina Piratininga · São Paulo, SP · 04444-000'),
  (2, 'jardim-selma', 'Jardim Selma', 'R. Pedro Fernandes de Aragão, 265 · Jardim Selma · São Paulo, SP');

-- durações supostas (Johen ajusta depois com a cliente)
insert into public.servicos (id, slug, nome, duracao_min, ordem) values
  (1, 'selagem',     'Selagem térmica',     150, 1),
  (2, 'alinhamento', 'Alinhamento capilar', 180, 2),
  (3, 'progressiva', 'Progressiva',         180, 3),
  (4, 'botox',       'Botox capilar',       120, 4),
  (5, 'coloracao',   'Coloração',           120, 5),
  (6, 'luzes',       'Luzes',               180, 6),
  (7, 'corte',       'Corte',                60, 7),
  (8, 'escova',      'Escova',               60, 8);

insert into public.admins (email) values ('johenartegrafica@gmail.com'), ('hjose5860@gmail.com');

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.admins a where a.email = lower(coalesce((select auth.jwt()) ->> 'email', '')));
$$;

alter table public.locais enable row level security;
alter table public.servicos enable row level security;
alter table public.agendamentos enable row level security;
alter table public.bloqueios enable row level security;
alter table public.admins enable row level security;

create policy "locais publicos" on public.locais for select to anon using (ativo);
create policy "locais logados" on public.locais for select to authenticated using (ativo or (select public.is_admin()));
create policy "servicos publicos" on public.servicos for select to anon using (ativo);
create policy "servicos logados" on public.servicos for select to authenticated using (ativo or (select public.is_admin()));
create policy "admin altera servicos" on public.servicos for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admin le agendamentos" on public.agendamentos for select to authenticated using ((select public.is_admin()));
create policy "admin altera agendamentos" on public.agendamentos for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admin le bloqueios" on public.bloqueios for select to authenticated using ((select public.is_admin()));
create policy "admin cria bloqueios" on public.bloqueios for insert to authenticated with check ((select public.is_admin()));
create policy "admin apaga bloqueios" on public.bloqueios for delete to authenticated using ((select public.is_admin()));

-- Intervalos indisponíveis de um dia para quem quer agendar em p_local (sem dados pessoais).
-- Atendimentos no outro local voltam "alargados" em 60 min de cada lado (deslocamento).
create or replace function public.horarios_ocupados(p_local smallint, p_dia date)
returns table (inicio timestamptz, fim timestamptz)
language sql stable security definer set search_path = ''
as $$
  with dia as (
    select tstzrange((p_dia::timestamp) at time zone 'America/Sao_Paulo', ((p_dia + 1)::timestamp) at time zone 'America/Sao_Paulo') as r
  )
  select case when a.local_id = p_local then lower(a.periodo) else lower(a.periodo) - interval '60 minutes' end,
         case when a.local_id = p_local then upper(a.periodo) else upper(a.periodo) + interval '60 minutes' end
    from public.agendamentos a, dia
   where a.status = 'confirmado' and a.folga && dia.r
  union all
  select lower(b.periodo), upper(b.periodo) from public.bloqueios b, dia where b.periodo && dia.r;
$$;

create or replace function public.agendar(p_servico smallint, p_local smallint, p_inicio timestamptz, p_nome text, p_telefone text, p_obs text default null)
returns uuid language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_dur int; v_fim timestamptz; v_local timestamp; v_local_fim timestamp;
  v_tel text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'); v_id uuid;
begin
  select duracao_min into v_dur from public.servicos where id = p_servico and ativo;
  if v_dur is null then raise exception 'Serviço indisponível' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.locais where id = p_local and ativo) then raise exception 'Escolha um dos endereços' using errcode = 'P0001'; end if;
  v_fim := p_inicio + make_interval(mins => v_dur);
  v_local := p_inicio at time zone 'America/Sao_Paulo';
  v_local_fim := v_fim at time zone 'America/Sao_Paulo';

  if p_inicio < now() + interval '2 hours' then raise exception 'Escolha um horário com pelo menos 2 horas de antecedência' using errcode = 'P0001'; end if;
  if p_inicio > now() + interval '60 days' then raise exception 'A agenda abre com até 60 dias de antecedência' using errcode = 'P0001'; end if;
  if extract(isodow from v_local) in (1, 7) then raise exception 'Não atendemos aos domingos e segundas' using errcode = 'P0001'; end if;
  if v_local::time < time '08:00' or v_local_fim::time > time '18:00' or v_local_fim::date <> v_local::date then
    raise exception 'Fora do horário de atendimento (8h às 18h)' using errcode = 'P0001'; end if;
  if extract(minute from v_local)::int % 30 <> 0 or extract(second from v_local) <> 0 then raise exception 'Horário inválido' using errcode = 'P0001'; end if;
  if char_length(btrim(coalesce(p_nome, ''))) < 2 then raise exception 'Informe seu nome' using errcode = 'P0001'; end if;
  if v_tel !~ '^[0-9]{10,13}$' then raise exception 'Informe um WhatsApp válido com DDD' using errcode = 'P0001'; end if;
  if (select count(*) from public.agendamentos where telefone = v_tel and status = 'confirmado' and upper(periodo) > now()) >= 3 then
    raise exception 'Você já tem 3 horários marcados. Fale no WhatsApp' using errcode = 'P0001'; end if;
  if exists (select 1 from public.bloqueios b where b.periodo && tstzrange(p_inicio, v_fim)) then
    raise exception 'Esse horário acabou de ser ocupado. Escolha outro' using errcode = 'P0001'; end if;
  begin
    insert into public.agendamentos (servico_id, local_id, periodo, folga, nome, telefone, obs)
    values (p_servico, p_local, tstzrange(p_inicio, v_fim),
            tstzrange(p_inicio - interval '30 minutes', v_fim + interval '30 minutes'),
            btrim(p_nome), v_tel, nullif(btrim(coalesce(p_obs, '')), ''))
    returning id into v_id;
  exception when exclusion_violation then
    raise exception 'Esse horário acabou de ser ocupado. Escolha outro' using errcode = 'P0001';
  end;
  return v_id;
end;
$$;

revoke all on function public.agendar(smallint, smallint, timestamptz, text, text, text) from public;
revoke all on function public.horarios_ocupados(smallint, date) from public;
revoke all on function public.is_admin() from public;
grant execute on function public.agendar(smallint, smallint, timestamptz, text, text, text) to anon, authenticated;
grant execute on function public.horarios_ocupados(smallint, date) to anon, authenticated;
grant execute on function public.is_admin() to authenticated;
