-- Contadores e filtro das abas de status de conversas.
-- SQL + leitura de tabelas → vive em 04_functions_post_tables (após 03_models).
-- Espelha a migration 20260717120100_conversation_status.sql.

create or replace function public.conversation_status_counts(org_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with convs as (
    select
      c.id,
      c.status,
      (c.extra ->> 'paused')::timestamptz as paused
    from public.conversations c
    where c.organization_id = org_id
  ),
  last_out as (
    select distinct on (m.conversation_id)
      m.conversation_id,
      m.status
    from public.messages m
    where m.organization_id = org_id
      and m.direction = 'outgoing'
    order by m.conversation_id, m.created_at desc
  )
  select jsonb_build_object(
    'aberto',     count(*) filter (where c.status in ('active', 'aberto')),
    'andamento',  count(*) filter (where c.status = 'andamento'),
    'finalizado', count(*) filter (where c.status = 'finalizado'),
    'ia',         count(*) filter (
                    where c.status <> 'finalizado'
                      and (c.paused is null
                           or c.paused < now() - interval '12 hours')
                  ),
    'erro',       count(*) filter (where lo.status ? 'failed')
  )
  from convs c
  left join last_out lo on lo.conversation_id = c.id;
$$;

create or replace function public.conversations_with_send_error(org_id uuid)
returns setof uuid
language sql
stable
set search_path = ''
as $$
  select conversation_id from (
    select distinct on (m.conversation_id)
      m.conversation_id,
      m.status
    from public.messages m
    where m.organization_id = org_id
      and m.direction = 'outgoing'
    order by m.conversation_id, m.created_at desc
  ) last_out
  where last_out.status ? 'failed';
$$;
