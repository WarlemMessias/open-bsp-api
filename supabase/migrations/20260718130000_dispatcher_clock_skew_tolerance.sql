-- O trigger imediato de dispatch pulava mensagens cujo `timestamp` (relógio do
-- CLIENTE) estava alguns segundos à frente do now() do servidor — comum em
-- mídia pequena (áudio) que entra no banco instantaneamente. Resultado: caía no
-- cron de fallback (1min+). Damos 30s de tolerância de skew: mensagens ~agora
-- despacham na hora; agendamentos reais (minutos/horas à frente) ainda esperam.

drop trigger if exists handle_outgoing_message_to_dispatcher on public.messages;

create trigger handle_outgoing_message_to_dispatcher
after insert
on public.messages
for each row
when (
  new.direction = 'outgoing'::public.direction
  and new.timestamp <= now() + interval '30 seconds'
  and (new.status ->> 'pending') is not null
)
execute function public.dispatcher_edge_function();
