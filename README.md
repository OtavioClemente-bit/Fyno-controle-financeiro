# Fyno - Controle Financeiro

**Fyno** é um aplicativo de controle financeiro pessoal e acompanhamento de investimentos, criado com foco em organização, educação financeira e facilidade de uso.

O projeto nasceu como uma solução prática para ajudar pessoas que têm dificuldade em controlar receitas, despesas, aportes e evolução patrimonial. Além do desenvolvimento técnico, o projeto também pode ser utilizado como atividade de extensão acadêmica, aproximando tecnologia e educação financeira da comunidade.

---

## Objetivo do projeto

Desenvolver uma ferramenta simples e acessível para auxiliar usuários no registro, acompanhamento e análise da sua vida financeira, incentivando hábitos de organização, planejamento e consciência sobre investimentos.

---

## Problema identificado

Muitas pessoas ainda controlam suas finanças de forma manual, por anotações soltas, planilhas desorganizadas ou apenas pela memória. Isso dificulta a visualização da real situação financeira, aumenta o risco de endividamento e prejudica a construção de uma reserva ou carteira de investimentos.

O Fyno busca resolver esse problema oferecendo um sistema simples para centralizar informações financeiras e facilitar a tomada de decisão.

---

## Funcionalidades previstas

- Cadastro de receitas e despesas
- Cadastro de investimentos
- Registro de aportes mensais
- Controle de saldo
- Visualização da carteira financeira
- Relatórios simples
- Histórico de movimentações
- Interface intuitiva
- Organização dos dados em banco de dados local

---

## Tecnologias utilizadas

- Python
- SQLite
- Tkinter
- Git e GitHub

---

## Estrutura sugerida do projeto

```text
Fyno-controle-financeiro/
├── app/
│   ├── main.py
│   ├── database.py
│   ├── models.py
│   ├── services.py
│   └── interface.py
├── docs/
│   └── projeto-extensao.md
├── tests/
├── requirements.txt
├── .gitignore
└── README.md
```

---

## Como executar

Clone o repositório:

```bash
git clone https://github.com/OtavioClemente-bit/Fyno-controle-financeiro.git
```

Acesse a pasta do projeto:

```bash
cd Fyno-controle-financeiro
```

Crie um ambiente virtual:

```bash
python -m venv .venv
```

Ative o ambiente virtual no Windows:

```bash
.venv\Scripts\activate
```

Instale as dependências:

```bash
pip install -r requirements.txt
```

Execute o projeto:

```bash
python app/main.py
```

---

## Aplicação social do projeto

Este projeto pode ser utilizado em uma ação de extensão universitária voltada à educação financeira da comunidade. A proposta é apresentar uma ferramenta simples que ajude usuários a entender melhor sua organização financeira, acompanhar investimentos e desenvolver hábitos mais conscientes no uso do dinheiro.

---

## Roadmap

- [ ] Criar estrutura inicial do projeto
- [ ] Implementar banco de dados SQLite
- [ ] Criar tela principal
- [ ] Implementar cadastro de transações
- [ ] Implementar cadastro de investimentos
- [ ] Criar relatório de saldo
- [ ] Criar relatório de carteira
- [ ] Testar com usuários reais
- [ ] Coletar feedback da comunidade
- [ ] Documentar resultados da atividade de extensão

---

## Autor

Desenvolvido por **Otavio Clemente**.

GitHub: [@OtavioClemente-bit](https://github.com/OtavioClemente-bit)
