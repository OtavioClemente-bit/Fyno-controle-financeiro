# Serviço seguro de nomes de produtos

Este Worker recebe somente os nomes brutos dos produtos, consulta a Responses
API com Structured Outputs e devolve nomes padronizados. Preço, foto, QR Code e
outros dados financeiros não são enviados.

## Configuração

1. Instale as dependências com `npm install`.
2. Para desenvolvimento, copie `.dev.vars.example` para `.dev.vars`.
3. Em produção, grave os segredos com:
   - `npx wrangler secret put OPENAI_API_KEY`
   - `npx wrangler secret put SAFETY_SALT`
4. Publique com `npm run deploy`.
5. Gere o app apontando para o Worker:

   `flutter build appbundle --release --dart-define=FYNO_PRODUCT_AI_ENDPOINT=https://SEU-WORKER.workers.dev`

Antes de abrir o serviço ao público, configure uma regra de rate limiting no
Cloudflare para este endpoint. A chave da OpenAI fica exclusivamente nos
segredos do Worker e não deve ser copiada para o Flutter.
