# Checklist de publicação do Fyno

## Segurança dos dados

Abordagem conservadora recomendada para a versão 1.10.0:

- **O app coleta ou compartilha dados obrigatórios?** Sim.
- **Compartilha dados com terceiros?** Não. O Google atua na autenticação e no
  Drive para executar a ação solicitada pelo usuário; não há venda, anúncios ou
  perfil publicitário.
- **Dados criptografados em trânsito?** Sim, para todo tráfego do aplicativo.
- **Mecanismo de exclusão?** Sim, diretamente no aplicativo para os backups do
  Drive e para os dados locais.

Tipos opcionais a declarar como coletados quando o backup Google for usado:

- Informações pessoais: endereço de e-mail e identificador do usuário.
- Informações financeiras: histórico de compras e outras informações financeiras.
- Fotos: imagens de comprovantes escolhidas pelo usuário.
- Outros conteúdos gerados pelo usuário: títulos, observações, categorias,
  produtos, veículos e registros de abastecimento.

Finalidades: funcionalidade do app e gerenciamento da conta. Não usar publicidade,
marketing, análise, personalização comercial ou prevenção de fraude como finalidade.

## Permissões e privacidade

- Câmera: opcional, usada no leitor de QR Code; a leitura ao vivo não salva foto.
- Acesso a notificações: ativação manual nas configurações do Android, somente
  para apps escolhidos e com revisão antes de salvar.
- Internet: NFC-e online, Google Sign-In e Google Drive.
- Sem SMS, registro de chamadas, contatos, localização, armazenamento amplo,
  acessibilidade ou ID de publicidade.

## Publicação

- Faixa recomendada: teste fechado principal.
- Versão: `1.10.0` (`versionCode 10`).
- Necessário alcançar 12 testadores inscritos por 14 dias para pedir produção.
- Não promover para produção antes de concluir o período e revisar o relatório
  de pré-lançamento.
