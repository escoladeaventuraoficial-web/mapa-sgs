-- Testes das regras do SGS. Rodar com supabase/tests/run.sh (PostgreSQL local, sem Supabase).
\set ON_ERROR_STOP 1
SET client_min_messages = warning;
\o /dev/null

CREATE FUNCTION pg_temp.espera_erro(p_sql text, p_trecho text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF position(p_trecho IN SQLERRM) = 0 THEN
      RAISE EXCEPTION 'Erro inesperado em [%]: %', p_sql, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'Deveria falhar: %', p_sql;
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.espera_erro(text, text) TO authenticated;

-- Usuários: o primeiro vira administrador da plataforma e Responsável da empresa fundadora.
-- Os demais entram sem empresa até receberem convite.
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
 ('00000000-0000-0000-0000-000000000001', 'vagner@exemplo.invalid', '{"name":"Responsável Teste"}'),
 ('00000000-0000-0000-0000-000000000002', 'autor@exemplo.invalid', '{}');
DO $$ BEGIN
  ASSERT (SELECT admin_plataforma FROM perfis WHERE email = 'vagner@exemplo.invalid'), 'primeiro é admin da plataforma';
  ASSERT (SELECT papel::text || ativo FROM membros m JOIN empresas e ON e.id = m.empresa_id
           WHERE e.nome = 'Trilhas do Sul' AND m.perfil_id = '00000000-0000-0000-0000-000000000001') = 'admin_sgstrue', 'primeiro é Responsável';
  ASSERT NOT EXISTS (SELECT 1 FROM membros WHERE perfil_id = '00000000-0000-0000-0000-000000000002'), 'sem convite, sem empresa';
END $$;

-- Itens e produtos de referência.
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM itens_mapa) = 34, 'itens do mapa';
  ASSERT (SELECT count(*) FROM itens_mapa WHERE escopo = 'produto') = 11, 'itens de produto';
  ASSERT (SELECT nome FROM produtos WHERE piloto) = 'Poço de Ferro', 'piloto';
  ASSERT (SELECT e.nome FROM produtos p JOIN empresas e ON e.id = p.empresa_id WHERE p.piloto) = 'Trilhas do Sul', 'piloto é da Trilhas do Sul';
END $$;

SET ROLE authenticated;

-- Usuário sem empresa não vê nada e não escreve.
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM produtos) = 0, 'sem empresa não lê';
  ASSERT (SELECT count(*) FROM itens_mapa) = 0, 'sem empresa não lê o mapa';
  ASSERT (SELECT count(*) FROM empresas) = 0, 'sem empresa não vê empresas';
END $$;
SELECT pg_temp.espera_erro($$INSERT INTO produtos (id, nome) VALUES ('x', 'X')$$, 'Informe a empresa');
SELECT pg_temp.espera_erro($$UPDATE perfis SET papel = 'admin_sgs', ativo = true WHERE id = auth.uid()$$, 'definido por empresa');
SELECT pg_temp.espera_erro($$UPDATE perfis SET admin_plataforma = true WHERE id = auth.uid()$$, 'definido por empresa');
SELECT pg_temp.espera_erro($$SELECT * FROM sgs_admin_empresas()$$, 'administrador da plataforma');
SELECT pg_temp.espera_erro($$SELECT sgs_convidar('00000000-0000-4000-8000-000000000001', 'x@exemplo.invalid', 'admin_sgs')$$, 'Só o responsável');

-- Responsável convida a equipe: quem já tem login entra na hora; quem não tem, entra no cadastro.
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
SELECT sgs_convidar('00000000-0000-4000-8000-000000000001', ' Autor@Exemplo.invalid ', 'autor');
SELECT sgs_convidar('00000000-0000-4000-8000-000000000001', 'campo@exemplo.invalid', 'equipe_campo');
SELECT sgs_convidar('00000000-0000-4000-8000-000000000001', 'ia@exemplo.invalid', 'leitura');
SELECT pg_temp.espera_erro($$SELECT sgs_convidar('00000000-0000-4000-8000-000000000001', 'ia2@exemplo.invalid', 'agente_ia')$$, 'Agente de IA');
SELECT pg_temp.espera_erro($$SELECT sgs_convidar('00000000-0000-4000-8000-000000000001', 'autor@exemplo.invalid', 'revisor')$$, 'já faz parte');
RESET ROLE;
INSERT INTO auth.users (id, email) VALUES
 ('00000000-0000-0000-0000-000000000003', 'campo@exemplo.invalid'),
 ('00000000-0000-0000-0000-000000000004', 'IA@exemplo.invalid');
SET ROLE authenticated;
UPDATE membros SET papel = 'agente_ia' WHERE perfil_id = '00000000-0000-0000-0000-000000000004';
DO $$ BEGIN
  ASSERT (SELECT string_agg(papel::text, ',' ORDER BY perfil_id) FROM membros) = 'admin_sgs,autor,equipe_campo,agente_ia', 'convites aceitos';
  ASSERT (SELECT count(*) FROM convites WHERE aceito_em IS NULL) = 0, 'nenhum convite pendente';
  ASSERT (SELECT count(*) FROM perfis) = 4, 'Responsável vê as pessoas da empresa';
END $$;
-- O SGS nunca fica sem responsável ativo.
SELECT pg_temp.espera_erro($$UPDATE membros SET ativo = false WHERE perfil_id = auth.uid()$$, 'pelo menos um responsável');
SELECT pg_temp.espera_erro($$UPDATE membros SET papel = 'leitura' WHERE perfil_id = auth.uid()$$, 'pelo menos um responsável');
SELECT pg_temp.espera_erro($$UPDATE empresas SET situacao = 'suspensa'$$, 'permission denied');
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
UPDATE membros SET papel = 'admin_sgs' WHERE perfil_id = auth.uid();   -- a política ignora
DO $$ BEGIN ASSERT (SELECT papel::text FROM membros) = 'autor', 'autor não se promove'; END $$;
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- Produtos e progresso.
INSERT INTO produtos (id, nome, atividades) VALUES ('tirolesa-teste', 'Tirolesa Teste', ARRAY['Tirolesa']);
SELECT pg_temp.espera_erro($$INSERT INTO produtos (id, nome) VALUES ('outra', 'tirolesa teste')$$, 'produtos_nome_unico');
SELECT pg_temp.espera_erro($$DELETE FROM produtos WHERE id = 'tirolesa-teste'$$, 'permission denied');
UPDATE produtos SET arquivado = true WHERE id = 'tirolesa-teste';
INSERT INTO progresso_itens (item) VALUES ('d_politica');
INSERT INTO progresso_itens (item, produto_id) VALUES ('d_pae', 'poco-de-ferro');
SELECT pg_temp.espera_erro($$INSERT INTO progresso_itens (item, produto_id) VALUES ('d_politica', 'poco-de-ferro')$$, 'é da empresa');
SELECT pg_temp.espera_erro($$INSERT INTO progresso_itens (item) VALUES ('d_inventario')$$, 'precisa de um produto');
SELECT pg_temp.espera_erro($$INSERT INTO progresso_itens (item) VALUES ('d_politica')$$, 'progresso_unico');
SELECT sgs_marcar_item('d_politica', NULL, false);
SELECT sgs_marcar_item('d_pae', 'poco-de-ferro', true);
SELECT sgs_marcar_item('d_escopo', NULL, true);
DO $$ BEGIN
  ASSERT (SELECT pronto FROM progresso_itens WHERE item = 'd_politica') = false, 'desmarcar';
  ASSERT (SELECT count(*) FROM progresso_itens) = 3, 'sem duplicar';
END $$;
SELECT pg_temp.espera_erro($$SELECT sgs_marcar_item('d_pae', NULL, true)$$, 'precisa de um produto');

-- Documento da empresa e documento do produto, sem código.
INSERT INTO documentos (requisito, titulo, item) VALUES ('4.1', 'Contexto da Organização', 'd_contexto');
INSERT INTO documentos (requisito, titulo, produto_id, item) VALUES ('8.2', 'PAE', 'poco-de-ferro', 'd_pae');
SELECT pg_temp.espera_erro($$INSERT INTO documentos (requisito, titulo) VALUES ('4.1', 'Outro')$$, 'documentos_unicos');
DO $$ BEGIN
  ASSERT (SELECT nome FROM v_documentos WHERE requisito = '8.2') = 'Documento 8.2 – PAE – Poço de Ferro', 'nome do documento';
END $$;

-- Agente de IA cria rascunho 1.0, mas não muda estado.
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004';
INSERT INTO versoes (documento_id, conteudo) SELECT id, '{"itens":[]}' FROM documentos WHERE requisito = '4.1';
DO $$ BEGIN
  ASSERT (SELECT versao FROM versoes v JOIN documentos d ON d.id = v.documento_id WHERE d.requisito = '4.1') = '1.0', 'primeira é 1.0';
  ASSERT (SELECT data_criacao FROM versoes WHERE id = 1) IS NULL, 'sem data de criação no rascunho';
END $$;
SELECT pg_temp.espera_erro($$SELECT sgs_transicionar(1, 'em_revisao')$$, 'não pode mudar o estado');
SELECT pg_temp.espera_erro($$INSERT INTO versoes (documento_id, estado) VALUES (1, 'vigente')$$, 'nasce como Rascunho');

-- Autor edita o rascunho e envia para revisão; não aprova.
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
UPDATE versoes SET conteudo = '{"itens":[{"fator":"F"}]}' WHERE id = 1;
SELECT pg_temp.espera_erro($$UPDATE versoes SET estado = 'aprovado' WHERE id = 1$$, 'só muda pela função');
SELECT pg_temp.espera_erro($$INSERT INTO versoes (documento_id) VALUES (1)$$, 'duplicate key');
SELECT sgs_transicionar(1, 'em_revisao');
SELECT pg_temp.espera_erro($$SELECT sgs_transicionar(1, 'aprovado')$$, 'não permitida');
UPDATE versoes SET conteudo = '{}' WHERE id = 1;   -- fora de Rascunho: a política ignora
DO $$ BEGIN ASSERT (SELECT conteudo FROM versoes WHERE id = 1) <> '{}'::jsonb, 'versão em revisão congelada'; END $$;

-- Responsável aprova (data de criação preenchida) e torna vigente.
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
SELECT sgs_transicionar(1, 'aprovado', 'Primeira versão aprovada');
DO $$ BEGIN ASSERT (SELECT data_criacao FROM versoes WHERE id = 1) = current_date, 'data de criação na aprovação'; END $$;
SELECT sgs_transicionar(1, 'vigente');

-- Revisão 1.1: ao ficar vigente, a 1.0 vira Substituída; data de criação não muda.
SELECT sgs_nova_versao(1, 'Inclusão de item SWOT') AS nv \gset
SELECT sgs_transicionar(:nv, 'em_revisao');
SELECT sgs_transicionar(:nv, 'aprovado');
SELECT sgs_transicionar(:nv, 'vigente');
DO $$ BEGIN
  ASSERT (SELECT versao || estado FROM versoes WHERE documento_id = 1 AND estado = 'vigente') = '1.1vigente', 'nova vigente';
  ASSERT (SELECT estado::text FROM versoes WHERE id = 1) = 'substituido', 'anterior substituída';
  ASSERT (SELECT data_criacao FROM versoes WHERE documento_id = 1 AND versao = '1.1') IS NULL, 'data de criação só na primeira';
  ASSERT (SELECT count(*) FROM versoes WHERE documento_id = 1 AND estado = 'vigente') = 1, 'uma vigente';
  ASSERT (SELECT count(*) FROM transicoes_versao WHERE versao_id = 1) = 5, 'histórico da 1.0';
END $$;
SELECT pg_temp.espera_erro($$DELETE FROM versoes WHERE id = 1$$, 'permission denied');

-- Nomes no rodapé: autor vê o nome do responsável, sem acesso à tabela de perfis.
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM perfis) = 1, 'autor só vê o próprio perfil';
  ASSERT (SELECT nome FROM sgs_pessoas(ARRAY['00000000-0000-0000-0000-000000000001'::uuid])) = 'Responsável Teste', 'nome do responsável';
  ASSERT (SELECT nome FROM sgs_pessoas(ARRAY['00000000-0000-0000-0000-000000000002'::uuid])) = 'autor@exemplo.invalid', 'sem nome usa e-mail';
END $$;
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- Equipe de campo só vê a versão vigente.
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
DO $$ BEGIN ASSERT (SELECT count(*) FROM versoes) = 1, 'campo vê só vigente'; END $$;
SELECT pg_temp.espera_erro($$SELECT sgs_marcar_item('d_escopo', NULL, false)$$, 'row-level security');
DO $$ BEGIN ASSERT (SELECT count(*) FROM sgs_pessoas(ARRAY['00000000-0000-0000-0000-000000000001'::uuid])) = 1, 'campo vê nomes'; END $$;
SELECT pg_temp.espera_erro($$INSERT INTO assinaturas VALUES ('00000000-0000-0000-0000-000000000001', 'data:image/png;base64,AA')$$, 'row-level security');
INSERT INTO assinaturas (perfil_id, imagem) VALUES ('00000000-0000-0000-0000-000000000003', 'data:image/png;base64,AA');
SELECT pg_temp.espera_erro($$INSERT INTO assinaturas VALUES ('00000000-0000-0000-0000-000000000003', 'x')$$, 'assinaturas_imagem_check');
SELECT pg_temp.espera_erro($$DELETE FROM assinaturas$$, 'permission denied');
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
UPDATE assinaturas SET imagem = 'data:image/png;base64,BB';   -- de outra pessoa: a política ignora
DO $$ BEGIN
  ASSERT (SELECT imagem FROM assinaturas) = 'data:image/png;base64,AA', 'não altera assinatura alheia';
END $$;
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';

\ir isolamento.sql

RESET ROLE;
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM auditoria WHERE tabela = 'versoes') >= 8, 'auditoria das versões';
  ASSERT (SELECT count(*) FROM auditoria WHERE usuario_id IS NOT NULL) > 0, 'auditoria com usuário';
END $$;
SELECT pg_temp.espera_erro($$DELETE FROM auditoria$$, 'só aceita inclusão');

\o
\echo 'Todos os testes passaram.'
