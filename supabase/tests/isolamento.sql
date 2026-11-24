-- Separação entre empresas (incluído por regras.sql, já com SET ROLE authenticated).
-- Empresa fictícia A: criada pelo site, aguarda liberação, depois funciona sem enxergar a Trilhas do Sul.
RESET ROLE;
INSERT INTO auth.users (id, email) VALUES
 ('00000000-0000-0000-0000-0000000000a1', 'dona-a@exemplo.invalid'),
 ('00000000-0000-0000-0000-0000000000a2', 'equipe-a@exemplo.invalid');
SET ROLE authenticated;

SET request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
SELECT sgs_criar_empresa('Aventura Teste A', '12.345.678/0001-90', 'Exemplo', 'sc', 'Dona Teste') AS emp_a \gset
SELECT set_config('t.emp_a', :'emp_a', false);
SELECT pg_temp.espera_erro($$SELECT sgs_criar_empresa('Outra')$$, 'aguardando liberação');
DO $$ BEGIN
  ASSERT (SELECT situacao::text || cnpj || uf FROM empresas) = 'aguardando12345678000190SC', 'empresa nasce aguardando';
  ASSERT (SELECT nome FROM perfis WHERE id = auth.uid()) = 'Dona Teste', 'nome da pessoa';
  ASSERT (SELECT count(*) FROM itens_mapa) = 0, 'aguardando: ainda sem mapa';
END $$;
SELECT pg_temp.espera_erro(format($$INSERT INTO produtos (id, empresa_id, nome) VALUES ('a-rapel', %L, 'Rapel A')$$, :'emp_a'), 'row-level security');
SELECT pg_temp.espera_erro(format($$SELECT sgs_convidar(%L, 'equipe-a@exemplo.invalid', 'autor')$$, :'emp_a'), 'Só o responsável');
SELECT pg_temp.espera_erro(format($$SELECT sgs_definir_situacao_empresa(%L, 'ativa')$$, :'emp_a'), 'administrador da plataforma');

-- Vagner (administrador da plataforma) vê a lista e libera, mas não vê os dados da empresa A.
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM sgs_admin_empresas()) = 3, 'admin vê todas as empresas';
  ASSERT (SELECT responsavel_email FROM sgs_admin_empresas() WHERE nome = 'Aventura Teste A') = 'dona-a@exemplo.invalid', 'quem criou';
END $$;
SELECT sgs_definir_situacao_empresa(:'emp_a', 'ativa');

-- Dona da empresa A trabalha no próprio SGS.
SET request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
INSERT INTO produtos (id, empresa_id, nome) VALUES ('a-rapel', :'emp_a', 'Rapel A');
INSERT INTO produtos (id, nome) VALUES ('a-poco', 'Poço de Ferro');   -- mesmo nome da Trilhas: permitido; empresa padrão
INSERT INTO documentos (requisito, titulo, item) VALUES ('4.1', 'Contexto da Organização', 'd_contexto');  -- mesmo requisito da Trilhas
INSERT INTO versoes (documento_id, conteudo) SELECT id, '{"empresa":"A"}' FROM documentos;
SELECT sgs_marcar_item('d_pae', 'a-rapel', true);
SELECT sgs_marcar_item(:'emp_a', 'd_politica', NULL, true);
SELECT sgs_convidar(:'emp_a', 'equipe-a@exemplo.invalid', 'revisor');
INSERT INTO assinaturas (perfil_id, imagem) VALUES (auth.uid(), 'data:image/png;base64,A1');
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM empresas) = 1, 'A vê só a própria empresa';
  ASSERT (SELECT string_agg(nome, ',' ORDER BY nome) FROM produtos) = 'Poço de Ferro,Rapel A', 'A vê só os próprios produtos';
  ASSERT (SELECT count(*) FROM documentos) = 1, 'A vê só os próprios documentos';
  ASSERT (SELECT count(*) FROM versoes) = 1, 'A vê só as próprias versões';
  ASSERT (SELECT count(*) FROM transicoes_versao) = 1, 'A vê só o próprio histórico';
  ASSERT (SELECT count(*) FROM progresso_itens) = 2, 'A vê só o próprio progresso';
  ASSERT (SELECT count(*) FROM perfis) = 2, 'A vê a si e a equipe A';
  ASSERT (SELECT count(*) FROM assinaturas) = 1, 'A não vê assinaturas da Trilhas';
  ASSERT (SELECT count(*) FROM auditoria) > 0 AND NOT EXISTS (SELECT 1 FROM auditoria WHERE empresa_id <> current_setting('t.emp_a')::uuid), 'auditoria só da A';
  ASSERT (SELECT count(*) FROM sgs_pessoas(ARRAY['00000000-0000-0000-0000-000000000001'::uuid])) = 0, 'A não vê nomes da Trilhas';
  ASSERT (SELECT count(*) FROM v_documentos) = 1, 'visão respeita a empresa';
END $$;
-- Tentativas de mexer na Trilhas do Sul.
SELECT pg_temp.espera_erro($$INSERT INTO versoes (documento_id) SELECT 1$$, 'row-level security');
SELECT pg_temp.espera_erro($$SELECT sgs_transicionar(1, 'arquivado')$$, 'não encontrada');
SELECT pg_temp.espera_erro($$SELECT sgs_nova_versao(1, 'invasão')$$, 'não encontrada');
SELECT pg_temp.espera_erro($$SELECT sgs_marcar_item('d_pae', 'poco-de-ferro', false)$$, 'row-level security');
SELECT pg_temp.espera_erro($$SELECT sgs_convidar('00000000-0000-4000-8000-000000000001', 'x@exemplo.invalid', 'autor')$$, 'Só o responsável');
SELECT pg_temp.espera_erro(format($$INSERT INTO documentos (empresa_id, requisito, titulo, produto_id, item) VALUES (%L, '8.2', 'PAE', 'poco-de-ferro', 'd_pae')$$, :'emp_a'), 'row-level security');
UPDATE produtos SET nome = 'Invadido' WHERE id = 'poco-de-ferro';      -- a política ignora
UPDATE membros SET papel = 'leitura' WHERE empresa_id = '00000000-0000-4000-8000-000000000001';
SELECT pg_temp.espera_erro(format($$UPDATE produtos SET empresa_id = '00000000-0000-4000-8000-000000000001' WHERE id = 'a-rapel'$$), 'não muda de empresa');
SELECT pg_temp.espera_erro($$DELETE FROM empresas$$, 'permission denied');

-- Equipe A entrou pelo convite e vê só a empresa A.
SET request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a2';
DO $$ BEGIN
  ASSERT (SELECT papel::text FROM membros) = 'revisor', 'convite aceito no cadastro';
  ASSERT (SELECT count(*) FROM produtos) = 2, 'equipe A vê produtos da A';
  ASSERT (SELECT count(*) FROM assinaturas) = 1, 'equipe A vê assinatura da dona';
  ASSERT (SELECT count(*) FROM perfis) = 1, 'revisor só vê o próprio perfil';
END $$;

-- Trilhas do Sul não vê nada da empresa A.
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM produtos WHERE id LIKE 'a-%') = 0, 'Trilhas não vê produtos da A';
  ASSERT (SELECT count(*) FROM documentos) = 2, 'Trilhas vê só os seus documentos';
  ASSERT (SELECT nome FROM produtos WHERE id = 'poco-de-ferro') = 'Poço de Ferro', 'A não alterou a Trilhas';
END $$;
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM membros WHERE papel = 'leitura') = 0, 'A não alterou membros da Trilhas';
  ASSERT (SELECT count(*) FROM perfis) = 4, 'Trilhas não vê pessoas da A';
  ASSERT (SELECT count(*) FROM auditoria WHERE empresa_id = current_setting('t.emp_a')::uuid) = 0, 'Trilhas não vê auditoria da A';
END $$;

-- Suspensa: a empresa A perde o acesso, sem apagar nada.
SELECT sgs_definir_situacao_empresa(:'emp_a', 'suspensa');
SET request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM produtos) = 0, 'suspensa não lê';
  ASSERT (SELECT situacao::text FROM empresas) = 'suspensa', 'mas vê a situação';
END $$;
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
