-- O media-preprocessor (anotação de mídia por IA) só faz sentido pra mídia
-- RECEBIDA (contexto pro agente IA ler). Rodá-lo em mídia ENVIADA é trabalho
-- inútil (custo + latência) e, via pg_net, some contenção antes do dispatcher —
-- atrasando o envio de áudio/mídia. Restringe o gatilho a incoming.

drop trigger if exists handle_message_to_media_preprocessor on public.messages;

create trigger handle_message_to_media_preprocessor
after insert
on public.messages
for each row
when (
  new.direction = 'incoming'::public.direction
  and (new.status ->> 'pending') is not null
  and (new.content ->> 'type') = 'file'
)
execute function public.edge_function('/media-preprocessor', 'post');
