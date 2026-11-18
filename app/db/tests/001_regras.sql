-- Testes das regras do padrão TS-PG-GER-001. Rodar sobre um banco com migrações + seeds.
-- Cada bloco deve passar; qualquer falha interrompe com erro.
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

CREATE OR REPLACE FUNCTION pg_temp.deve_falhar(p_sql text, p_trecho text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF position(p_trecho IN SQLERRM) = 0 THEN
      RAISE EXCEPTION 'Falhou pelo motivo errado. Esperado "%", obtido "%"', p_trecho, SQLERRM;
    END IF;
    RAISE NOTICE 'ok: bloqueado (%)', p_trecho;
    RETURN;
  END;
  RAISE EXCEPTION 'Deveria ter falhado: %', p_sql;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.afirmar(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF NOT coalesce(p_cond, false) THEN RAISE EXCEPTION 'Falhou: %', p_msg; END IF;
  RAISE NOTICE 'ok: %', p_msg;
END $$;

-- 1. Seeds produziram o estado esperado
SELECT pg_temp.afirmar((SELECT versao FROM v_documentos_vigentes WHERE codigo = 'TS-POL-GER-001') = 'v1.0',
  'primeira aprovação de v0.1 vira v1.0');
SELECT pg_temp.afirmar((SELECT versao_em_andamento FROM v_lista_mestra WHERE codigo = 'TS-PAE-TST-001') = 'v2.0 (em_revisao)',
  'lista mestra mostra v2.0 em revisão ao lado da vigente');
SELECT pg_temp.afirmar(EXISTS (SELECT 1 FROM v_revisoes_a_vencer WHERE codigo = 'TS-POL-GER-001'),
  'política vigente há 350 dias aparece em revisões a vencer');
SELECT pg_temp.afirmar(EXISTS (SELECT 1 FROM v_acoes_atrasadas), 'ação atrasada aparece no painel');

-- 2. Código
SELECT pg_temp.deve_falhar($$INSERT INTO documentos (codigo, titulo, tipo, roteiro_sigla, vinculo_normativo, origem, responsavel_funcao, criado_por)
  VALUES ('TS-PAE-GER-009', 'x', 'PO', NULL, 'x', 'norma', 'x', 1)$$, 'codigo_formato');
SELECT pg_temp.deve_falhar($$INSERT INTO documentos (codigo, titulo, tipo, roteiro_sigla, vinculo_normativo, origem, responsavel_funcao, criado_por)
  VALUES ('TS-PO-GER-009', 'x', 'PO', 'TST', 'x', 'norma', 'x', 1)$$, 'codigo_formato');
SELECT pg_temp.deve_falhar($$INSERT INTO documentos (codigo, titulo, tipo, roteiro_sigla, vinculo_normativo, origem, responsavel_funcao, criado_por)
  VALUES ('TS-REG-TST-009', 'x', 'REG', 'TST', 'x', 'norma', 'x', 1)$$, 'documento_nao_e_registro');
SELECT pg_temp.deve_falhar($$INSERT INTO documentos (codigo, titulo, tipo, roteiro_sigla, vinculo_normativo, origem, responsavel_funcao, criado_por)
  VALUES ('TS-POL-GER-001', 'x', 'POL', NULL, 'x', 'norma', 'x', 1)$$, 'duplicate key');

-- 3. Versão nasce como rascunho, sem aprovação
SELECT pg_temp.deve_falhar($$INSERT INTO versoes (documento_id, maior, menor, autor_id, motivo, estado)
  VALUES ((SELECT id FROM documentos WHERE codigo='TS-POL-GER-001'), 9, 0, 1, 'x', 'vigente')$$, 'nasce como Rascunho');

-- 4. Estado só muda pela função; versão fora de rascunho fica congelada
SELECT pg_temp.deve_falhar($$UPDATE versoes SET estado = 'arquivado'
  WHERE id = (SELECT versao_id FROM v_documentos_vigentes WHERE codigo='TS-POL-GER-001')$$, 'só muda pela função');
SELECT pg_temp.deve_falhar($$UPDATE versoes SET conteudo = 'alterado'
  WHERE id = (SELECT versao_id FROM v_documentos_vigentes WHERE codigo='TS-POL-GER-001')$$, 'não pode ser alterada');
SELECT pg_temp.deve_falhar($$UPDATE versoes SET estado = 'em_revisao'
  WHERE documento_id = (SELECT id FROM documentos WHERE codigo='TS-PAE-TST-001') AND estado = 'em_revisao'$$, 'não pode ser alterada');
SELECT pg_temp.deve_falhar($$DELETE FROM versoes WHERE id = 1$$, 'não podem ser apagadas');

-- 5. Papéis
SELECT pg_temp.deve_falhar($$SELECT sgs_transicionar(
  (SELECT v.id FROM versoes v JOIN documentos d ON d.id = v.documento_id WHERE d.codigo='TS-PAE-TST-001' AND v.estado='em_revisao'),
  'aprovado', (SELECT id FROM usuarios WHERE papel='agente_ia'))$$, 'não pode mudar o estado');
SELECT pg_temp.deve_falhar($$SELECT sgs_transicionar(
  (SELECT v.id FROM versoes v JOIN documentos d ON d.id = v.documento_id WHERE d.codigo='TS-PAE-TST-001' AND v.estado='em_revisao'),
  'aprovado', (SELECT id FROM usuarios WHERE email='autor@demo.invalid'))$$, 'não permitida para o papel autor');
SELECT pg_temp.deve_falhar($$SELECT sgs_transicionar(
  (SELECT v.id FROM versoes v JOIN documentos d ON d.id = v.documento_id WHERE d.codigo='TS-PAE-TST-001' AND v.estado='em_revisao'),
  'vigente', (SELECT id FROM usuarios WHERE papel='admin_sgs'))$$, 'em_revisao → vigente não permitida');

-- 6. Troca de vigência: aprova v2.0 e torna vigente; v1.0 vira substituída; só uma vigente
DO $$
DECLARE
  u bigint := (SELECT id FROM usuarios WHERE papel='admin_sgs');
  d bigint := (SELECT id FROM documentos WHERE codigo='TS-PAE-TST-001');
  v2 bigint := (SELECT id FROM versoes WHERE documento_id = d AND estado = 'em_revisao');
BEGIN
  PERFORM sgs_transicionar(v2, 'aprovado', u, 'Aprovado após simulado');
  PERFORM sgs_transicionar(v2, 'vigente', u, 'Entra em vigor');
END $$;
SELECT pg_temp.afirmar((SELECT versao FROM v_documentos_vigentes WHERE codigo='TS-PAE-TST-001') = 'v2.0',
  'v2.0 passa a ser a vigente');
SELECT pg_temp.afirmar((SELECT estado FROM versoes v JOIN documentos d ON d.id=v.documento_id
  WHERE d.codigo='TS-PAE-TST-001' AND v.versao='v1.0') = 'substituido', 'v1.0 vira Substituído na mesma transação');
SELECT pg_temp.afirmar((SELECT count(*) FROM versoes v JOIN documentos d ON d.id=v.documento_id
  WHERE d.codigo='TS-PAE-TST-001' AND v.estado='vigente') = 1, 'só uma versão vigente por código');
SELECT pg_temp.afirmar((SELECT count(*) FROM transicoes_versao t JOIN versoes v ON v.id=t.versao_id
  JOIN documentos d ON d.id=v.documento_id WHERE d.codigo='TS-PAE-TST-001') = 9, 'histórico completo de transições preservado');

-- 7. Índice garante unicidade mesmo contornando a função
SELECT pg_temp.deve_falhar($t$DO $x$ BEGIN
  PERFORM set_config('sgs.transicao','on',true);
  UPDATE versoes SET estado='vigente' WHERE versao='v1.0'
    AND documento_id=(SELECT id FROM documentos WHERE codigo='TS-PAE-TST-001');
END $x$$t$, 'uma_vigente_por_documento');

-- 8. Recuperar versão antiga = nova versão com ciclo completo
SELECT pg_temp.deve_falhar($$SELECT sgs_transicionar(
  (SELECT v.id FROM versoes v JOIN documentos d ON d.id=v.documento_id WHERE d.codigo='TS-PAE-TST-001' AND v.versao='v1.0'),
  'vigente', (SELECT id FROM usuarios WHERE papel='admin_sgs'))$$, 'substituido → vigente não permitida');
DO $$
DECLARE
  base bigint := (SELECT v.id FROM versoes v JOIN documentos d ON d.id=v.documento_id
                   WHERE d.codigo='TS-PAE-TST-001' AND v.versao='v1.0');
  nova bigint;
BEGIN
  nova := sgs_nova_versao(base, (SELECT id FROM usuarios WHERE papel='agente_ia'), 'Proposta: recuperar texto da v1.0');
  PERFORM pg_temp.afirmar((SELECT versao || '/' || estado FROM versoes WHERE id = nova) = 'v3.0/rascunho',
    'recuperação gera v3.0 em Rascunho, criada pelo agente de IA');
END $$;

-- 9. Histórico e auditoria são somente inclusão
SELECT pg_temp.deve_falhar($$DELETE FROM transicoes_versao$$, 'só aceita inclusão');
SELECT pg_temp.deve_falhar($$UPDATE auditoria SET operacao='x'$$, 'só aceita inclusão');
SELECT pg_temp.afirmar((SELECT count(*) FROM auditoria WHERE tabela='versoes') > 0, 'alterações de versões ficam na auditoria');

-- 10. Registros e evidências
SELECT pg_temp.deve_falhar($$INSERT INTO registros (codigo, formulario_versao_id, roteiro_sigla, data, descricao, registrado_por)
  VALUES ('TS-REG-TST-001-2026-01-01', (SELECT versao_id FROM v_documentos_vigentes WHERE codigo='TS-POL-GER-001'),
          'TST', current_date, 'x', 1)$$, 'formulário (FOR)');
SELECT pg_temp.deve_falhar($$UPDATE requisito_vinculos SET situacao='implementacao_comprovada' WHERE roteiro_sigla='TST'$$,
  'exige evidência verificada');
DO $$
DECLARE vin bigint := (SELECT id FROM requisito_vinculos WHERE roteiro_sigla='TST');
BEGIN
  INSERT INTO evidencias (versao_id, requisito_vinculo_id, registro_id, descricao, data, verificada_por, verificada_em)
  VALUES ((SELECT versao_id FROM v_documentos_vigentes WHERE codigo='TS-PAE-TST-001'), vin,
          (SELECT id FROM registros LIMIT 1), 'Simulado fictício realizado', current_date,
          (SELECT id FROM usuarios WHERE papel='admin_sgs'), current_date);
  UPDATE requisito_vinculos SET situacao='implementacao_comprovada' WHERE id = vin;
  PERFORM pg_temp.afirmar(true, 'com evidência verificada, requisito passa a Implementação comprovada');
END $$;

-- 11. Ações
SELECT pg_temp.deve_falhar($$UPDATE acoes SET estado='concluida'$$, 'conclusao_com_evidencia');

\echo 'TODOS OS TESTES PASSARAM'
