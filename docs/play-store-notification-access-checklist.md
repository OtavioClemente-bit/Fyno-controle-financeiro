# Checklist de publicação — acesso às notificações

- Hospedar `privacy-policy-pt-BR.md` em uma URL HTTPS pública, ativa, sem bloqueio e sem PDF.
- Preencher o contato real na política e disponibilizar a mesma URL no app e na ficha da loja.
- Declarar no formulário Segurança dos dados o acesso e o processamento de notificações de acordo com a versão publicada.
- Gravar um vídeo de revisão mostrando: escolha de banco, divulgação destacada, consentimento, tela do Android e revisão de uma sugestão.
- Explicar nas notas de revisão que o recurso é opcional, local, limitado a bancos escolhidos e parte central do registro financeiro.
- Conferir o manifesto final do AAB: sem `QUERY_ALL_PACKAGES`, com apenas um `NotificationListenerService` e com `POST_NOTIFICATIONS` explicado exclusivamente pelos lembretes opcionais de revisão.
- Demonstrar que `POST_NOTIFICATIONS` só é solicitado quando o usuário agenda o primeiro lembrete e que negar a permissão mantém o lembrete visível dentro do Fyno.
- Testar recusa, pausa, lista vazia, revogação do Android, reinício do aparelho e atualização do app.
- Manter a captura desligada por padrão em instalações novas.
