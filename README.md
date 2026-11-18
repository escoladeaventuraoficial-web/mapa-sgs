# Mapa SGS · Trilhas do Sul

Repositório do Sistema de Gestão da Segurança (SGS) da Trilhas do Sul, conforme a ABNT NBR ISO 21101 (turismo de aventura).

| Pasta / arquivo | O que é |
|---|---|
| `index.html` | Mapa mental interativo da ISO 21101, publicado em sgsturismo.com.br. **Não alterar sem combinar**: é o site público. |
| `docs/padrao/` | Padrão de documentação do SGS (TS-PG-GER-001). |
| `modelos/` | Modelos de documento controlado (cabeçalho, bloco de controle, rodapé). |
| `app/` | Aplicação do SGS: banco de dados, API e painel (em construção). |
| `.env.example` | Modelo de variáveis de ambiente, sem segredos. |

## Situação

- **Fase 1 (atual):** padrão de documentação, modelos e banco de dados com regras de versão, testado com dados fictícios.
- Próximas fases: API com login e permissões por papel, painel (celular e computador), importação de acervo, chat com IA, publicação.

Nenhum dado real está neste repositório. Dados reais só entram após autorização do responsável pelo SGS.

Detalhes técnicos em [`app/README.md`](app/README.md).
