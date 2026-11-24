# SGS Turismo

Plataforma de Sistemas de Gestão da Segurança (SGS) por produto da Trilhas do Sul,
com o mapa interativo da ABNT NBR ISO 21101 (turismo de aventura).
- `index.html`: plataforma com login em sgsturismo.com.br (decisão de Vagner, 20/11/2026: substitui o
  mapa público; a versão pública antiga fica no histórico do Git).

## Como funciona

- **Tela inicial (`#/`)**: lista os produtos (roteiros) em cartões, com progresso, busca e o botão **Novo produto**.
  O Poço de Ferro é o piloto; os demais produtos de exemplo são fictícios e podem ser excluídos.
- **SGS do produto (`#/p/<id>`)**: abre o mapa da norma daquele produto, com o botão **Produtos** para voltar.
- **Jornada do cliente (`#/p/<id>/jornada`)**: aba ao lado de **Mapa do SGS**, com o mapa mental das etapas que o
  cliente vive para conhecer, comprar e fazer o passeio. Cada ponto de contato mostra os requisitos da ISO 21101 que toca
  e abre o requisito ou documento no mapa do SGS. Só visualização (sem preenchimento nem banco). O conteúdo fica em
  `JORNADA` no código: rascunho proposto em 23/11/2026 para o piloto Poço de Ferro, aguardando revisão de Vagner.
  A jornada cobre todos os requisitos de 4.1 a 10.2 (o ramo "Por trás de toda a jornada" traz os que o cliente não vê).
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

- **Entrar** (24/11/2026): e-mail e senha. Na tela de entrada há **Entrar**, **Criar conta**, **Esqueci minha senha**
  (e-mail com link para criar nova senha) e **Entrar com link no e-mail** (o jeito antigo, sem senha). Quem já entra
  pelo link pode criar uma senha pelo botão **Senha** no topo. A senha tem pelo menos 8 caracteres.
  No Supabase: Authentication › Sign In / Providers › Email precisa estar ligado (padrão). Se "Confirm email" estiver
  ligado, a conta nova recebe um e-mail de confirmação antes do primeiro acesso. O plano Free envia poucos e-mails por
  hora; para clientes reais, configure um SMTP próprio.

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
- Cada empresa tem o seu SGS (ver "Várias empresas" abaixo). Quem entra sem convite vê a tela **Criar minha empresa**;
  a empresa fica **aguardando liberação** até o administrador da plataforma liberar no botão **Empresas**.
- **Trazer a equipe**: o Responsável abre **Usuários**, digita o e-mail, escolhe o papel e toca em **Convidar**. A pessoa
  entra no site com esse mesmo e-mail e já cai na empresa. O Responsável também troca o papel, bloqueia e cancela convites.
  O banco não deixa a empresa ficar sem um Responsável ativo.
- Quem está em mais de uma empresa troca de empresa no seletor do topo.
- Se o cadastro aberto estiver desligado no Supabase (Authentication › Sign In / Providers › Allow new users to sign up),
  só entra quem for convidado pelo painel do Supabase (Authentication › Users › Invite user).

## Várias empresas (migração `20261124000002_multi_empresa.sql`, ainda não aplicada na produção)

- Cada empresa tem o seu SGS. Produtos, documentos, versões, histórico, progresso, decisões, auditoria e arquivos
  ganham `empresa_id`, e a RLS só deixa ler e escrever dentro das empresas em que a pessoa é membro ativo.
- `membros` guarda o papel **por empresa** (`perfis.papel` e `perfis.ativo` ficam só como histórico).
- **Criar empresa**: `sgs_criar_empresa()`. Quem cria vira Responsável dela. A empresa nasce **aguardando** e só
  funciona depois que o administrador da plataforma libera com `sgs_definir_situacao_empresa()` (decisão de Vagner,
  24/11/2026). Ele vê a lista com `sgs_admin_empresas()`, sem acesso aos documentos das empresas.
- **Convidar a equipe**: `sgs_convidar(empresa, email, papel)`. Se a pessoa já tem login entra na hora; senão, entra
  ao fazer o primeiro login com aquele e-mail. O site chama `sgs_aceitar_convites()` a cada login.
- Arquivos no Storage ficam em `documentos/<empresa_id>/...`.
- Tudo o que já existe vira da empresa **Trilhas do Sul**; os 2 produtos fictícios de exemplo são arquivados.
- O site envia o `empresa_id` da empresa aberta em todas as leituras e gravações.
- `supabase/tests/run.sh` roda dois cenários: banco novo com empresas fictícias (`regras.sql` + `isolamento.sql`)
  e a migração de um banco igual ao da produção (`legado_antes.sql` → `legado_depois.sql`).
