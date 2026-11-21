# SGS Turismo

Plataforma de Sistemas de Gestão da Segurança (SGS) por produto da Trilhas do Sul,
com o mapa interativo da ABNT NBR ISO 21101 (turismo de aventura).
- `index.html`: plataforma com login em sgsturismo.com.br (decisão de Vagner, 20/11/2026: substitui o
  mapa público; a versão pública antiga fica no histórico do Git).

## Como funciona

- **Tela inicial (`#/`)**: lista os produtos (roteiros) em cartões, com progresso, busca e o botão **Novo produto**.
  O Poço de Ferro é o piloto; os demais produtos de exemplo são fictícios e podem ser excluídos.
- **SGS do produto (`#/p/<id>`)**: abre o mapa da norma daquele produto, com o botão **Produtos** para voltar.
- **Separação dos dados** (decisão de 20/11/2026): documentos da empresa (contexto, política, funções,
  auditoria etc.) são únicos e valem para todos os produtos; documentos e registros de operação
  (contexto da atividade, inventário de perigos, procedimentos, competência do participante, termo, PAE,
  ficha, check-lists, simulados, incidentes, feedback) ficam separados por produto (`PROD_REFS` no código).
- Enquanto não há servidor, produtos e progresso ficam no `localStorage` do navegador
  (`sgs-produtos-v1`, `sgs-itens-empresa-v1`, `sgs-itens-produto-v1:<id>`). O progresso do mapa antigo
  (`sgs-mapa-itens-v1`) é migrado na primeira abertura: itens da empresa para a empresa, itens de operação
  para o Poço de Ferro.
- **Preenchimento de documentos** (requisito 4): no painel dos itens 4.1, 4.2 e 4.3 aparece a caixa
  “No SGS da Trilhas do Sul”, que abre a área de preenchimento em tela cheia, com etapas e a etapa
  **Revisar e aprovar** (pré-visualização no layout do documento). Os modelos ficam em `TPL` no código.
  Cada documento é uma linha em `documentos` e cada versão uma linha em `versoes` (conteúdo em JSON).
  A versão nasce 1.0 Rascunho, é salva automaticamente, vai para Em revisão, Aprovado (data de criação na
  primeira aprovação) e Vigente. Para mudar um documento vigente, cria-se uma nova versão (1.1).
  Os nomes no rodapé vêm da função `sgs_pessoas()`. O cabeçalho usa o logo `img/logo-trilhas-do-sul.png`;
  a assinatura de quem revisou e aprovou vem da tabela `assinaturas` (imagem protegida por RLS, fora do site público).

## Servidor (Supabase)

- `supabase/migrations/`: banco da plataforma (produtos, itens do mapa, progresso, documentos sem código,
  versões 1.0 → aprovação → vigência, transições, decisões, auditoria, segurança por linha e bucket privado
  de arquivos). `supabase/seed.sql` tem só **dados fictícios** para o ambiente de testes.
- `supabase/tests/run.sh`: aplica tudo num PostgreSQL local temporário (simulando o Supabase) e roda os
  testes de regras (`regras.sql`). Precisa do PostgreSQL instalado e de usuário que não seja root.
- O site se liga ao banco por `SGS_CONFIG` no `index.html` com a URL do projeto e a chave
  pública (anon). A chave anon é pública por desenho; os dados são protegidos pela RLS. Nunca coloque a
  chave `service_role` no site.
- No Supabase (Authentication › URL Configuration), o Site URL e as Redirect URLs precisam incluir o
  endereço da plataforma (ex.: `https://www.sgsturismo.com.br/`), senão o link de acesso por e-mail não volta para o site.
- Sem `SGS_CONFIG`, a plataforma funciona em modo local (só no navegador), útil para testes.
- O primeiro usuário que entrar vira **Responsável pelo SGS**. Depois disso, desative novos cadastros
  abertos no Supabase (Authentication › Sign In / Providers) ou libere os usuários um a um.
