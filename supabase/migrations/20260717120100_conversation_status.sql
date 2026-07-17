-- Status de conversas (Aberto / Andamento / Finalizados / IA / Erro)
-- Reaproveita o schema existente (nenhuma coluna nova):
--   conversations.status  → 'active'/'aberto' | 'andamento' | 'finalizado'
--   conversations.extra->>'paused' → janela de pausa de 12h da IA
--   messages.status ? 'failed' → falha permanente de envio (aba Erro)

-- Índice pros filtros das abas
create index if not exists conversations_org_status_idx
  on public.conversations using btree (organization_id, status);

-- Índice pro cálculo de Erro (última outgoing por conversa)
create index if not exists messages_conv_outgoing_created_idx
  on public.messages using btree (conversation_id, created_at desc)
  where direction = 'outgoing';

-- Contadores das abas (uma chamada retorna o jsonb pronto pros badges).
-- security invoker (default) → RLS aplica por agente.
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

-- Ids das conversas com erro de envio (pra aba Erro filtrar a lista)
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
