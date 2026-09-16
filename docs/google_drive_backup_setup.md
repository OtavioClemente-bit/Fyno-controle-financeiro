# Configuração do backup Google do Fyno

O código do aplicativo já usa somente o escopo `drive.appdata`, que dá acesso
à pasta privada do próprio Fyno no Google Drive. Falta vincular a assinatura do
aplicativo a um projeto Google Cloud antes de testar ou publicar.

## 1. Criar ou escolher o projeto

1. Abra o [Google Cloud Console](https://console.cloud.google.com/).
2. Crie ou selecione o projeto oficial do Fyno.
3. Em **APIs e serviços > Biblioteca**, ative a
   [Google Drive API](https://console.cloud.google.com/apis/library/drive.googleapis.com).
4. Configure a tela de consentimento OAuth com o nome `Fyno`, e-mail de suporte,
   domínio e links de política de privacidade/termos que serão usados na Play
   Store.
5. Em acesso a dados, mantenha somente o escopo solicitado pelo app:
   `https://www.googleapis.com/auth/drive.appdata`.

Esse escopo é classificado pelo Google como não sensível e não permite ao Fyno
ler arquivos comuns do Drive.

## 2. Registrar o Android

Em **APIs e serviços > Credenciais**, crie credenciais OAuth do tipo Android
para o pacote:

```text
com.fyno.app
```

Cadastre uma credencial para cada assinatura que será usada:

| Build | SHA-1 |
| --- | --- |
| Desenvolvimento local | `66:49:01:13:13:00:71:CF:12:B0:F9:00:8E:09:8A:1C:CB:8E:18:B0` |
| Release local do Fyno | `FB:66:BA:D2:F6:84:CF:A8:F7:60:AA:66:A5:72:20:F8:F4:B3:59:23` |
| Distribuição pela Play Store | `23:56:B4:E3:4A:50:6C:E0:47:E8:8E:12:F7:29:38:CB:23:A7:A8:06` |

O SHA da Play foi confirmado em **Protegido com o Google Play > Assinatura de
apps**. Ele é diferente do certificado usado para enviar o AAB e precisa da sua
própria credencial OAuth Android.

## 3. Criar o cliente Web usado pelo Android

Ainda em credenciais, crie um cliente OAuth do tipo **Aplicativo da Web**. Ele
é usado pelo Credential Manager do Android como `serverClientId`; não é uma
senha e não deve ser confundido com o cliente OAuth do tipo Android.

Crie um arquivo local `config/google_oauth.json` a partir deste modelo:

```json
{
  "FYNO_GOOGLE_SERVER_CLIENT_ID": "SEU_CLIENTE_WEB.apps.googleusercontent.com"
}
```

Execute e gere o AAB sempre com esse arquivo:

```powershell
flutter run --dart-define-from-file=config/google_oauth.json
flutter build appbundle --release --dart-define-from-file=config/google_oauth.json
```

Não existe `client secret` dentro do aplicativo. Nunca inclua um segredo OAuth,
senha do keystore ou chave de serviço em um `dart-define`.

## 4. Testar antes da publicação

1. Conecte uma conta Google na tela **Ajustes > Backup e restauração**.
2. Crie uma despesa, um produto, um veículo e anexe um comprovante.
3. Faça o backup e confirme que ele aparece no histórico.
4. Em outro emulador/aparelho, instale uma build assinada por uma credencial
   cadastrada, conecte a mesma conta e restaure a cópia.
5. Confirme lançamentos, itens, veículos, comprovantes e tema.
6. Teste também internet interrompida, cancelamento da conta e restauração de
   uma cópia antiga.

As notificações bancárias e a seleção dos aplicativos monitorados são
deliberadamente locais e não fazem parte do backup.

## 5. Checklist de privacidade e Play Store

- Atualize a política de privacidade para explicar que, somente após ação do
  usuário, o Fyno envia dados financeiros para a área privada da própria conta
  Google com a finalidade de backup e restauração.
- Informe que o desenvolvedor do Fyno não recebe nem consegue abrir essas
  cópias e que a transmissão usa HTTPS/TLS do Google Drive.
- Mantenha o backup como ação explícita do usuário. Esta implementação não
  transfere dados silenciosamente em segundo plano.
- Na tela de backup, o menu da conta permite excluir permanentemente todas as
  cópias da nuvem, sair da conta ou revogar o acesso do Fyno.
- Revise a seção **Segurança de dados** da Play Console. A orientação oficial
  do Google diz que um envio escolhido pelo usuário diretamente para a própria
  conta Drive pode não ser declarado como coleta quando o desenvolvedor não
  recebe nem acessa esses dados. A declaração final deve refletir também os
  demais recursos e SDKs presentes no aplicativo.
- Mesmo quando a conclusão for “nenhuma coleta”, mantenha uma política de
  privacidade pública e vinculada dentro do app e na Play Console.

## Referências oficiais

- [Google Drive appDataFolder](https://developers.google.com/workspace/drive/api/guides/appdata)
- [Flutter: usar APIs do Google](https://docs.flutter.dev/data-and-backend/google-apis)
- [Google Sign-In para Android no Flutter](https://pub.dev/packages/google_sign_in_android)
- [Segurança de dados da Play Console](https://support.google.com/googleplay/android-developer/answer/10787469)
- [Política de dados do usuário](https://support.google.com/googleplay/android-developer/answer/10144311)
