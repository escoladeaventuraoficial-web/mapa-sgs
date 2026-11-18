-- DADOS FICTÍCIOS PARA DEMONSTRAÇÃO. Não usar em produção.
-- Usa um roteiro fictício (TST) e pessoas fictícias com e-mails no domínio reservado .invalid.
BEGIN;

INSERT INTO usuarios (nome, email, papel) VALUES
  ('Responsável SGS (demo)', 'responsavel@demo.invalid', 'admin_sgs'),
  ('Revisora (demo)',        'revisora@demo.invalid',    'revisor'),
  ('Autor (demo)',           'autor@demo.invalid',       'autor'),
  ('Guia de campo (demo)',   'guia@demo.invalid',        'equipe_campo'),
  ('Agente de IA do SGS',    'agente-ia@demo.invalid',   'agente_ia');

INSERT INTO roteiros (sigla, nome, descricao) VALUES
  ('TST', 'Roteiro de Demonstração', 'Roteiro fictício usado apenas para testes');

-- Documentos fictícios
INSERT INTO documentos (codigo, titulo, tipo, roteiro_sigla, vinculo_normativo, origem, responsavel_funcao, classificacao, criado_por)
SELECT x.codigo, x.titulo, x.tipo, x.roteiro, x.vinculo, x.origem::origem_obrigacao, x.resp, x.classif::classificacao_acesso,
       (SELECT id FROM usuarios WHERE email = 'responsavel@demo.invalid')
FROM (VALUES
  ('TS-POL-GER-001', '[DEMO] Política de Segurança', 'POL', NULL, 'ISO 21101, cap. 5 (cláusula pendente de verificação)', 'norma', 'Direção', 'interno'),
  ('TS-PAE-TST-001', '[DEMO] PAE – Roteiro de Demonstração', 'PAE', 'TST', 'ISO 21101, cap. 8 (cláusula pendente de verificação)', 'norma', 'Coordenador de operação', 'equipe_campo'),
  ('TS-FOR-TST-001', '[DEMO] Checklist pré-atividade', 'FOR', 'TST', 'ISO 21101, cap. 8 (cláusula pendente de verificação)', 'regra_interna', 'Coordenador de operação', 'equipe_campo')
) AS x(codigo, titulo, tipo, roteiro, vinculo, origem, resp, classif);

-- Política: v0.1 criada pelo agente de IA, revisada e aprovada (vira v1.0) e tornada vigente.
DO $$
DECLARE
  u_resp bigint := (SELECT id FROM usuarios WHERE email = 'responsavel@demo.invalid');
  u_rev  bigint := (SELECT id FROM usuarios WHERE email = 'revisora@demo.invalid');
  u_aut  bigint := (SELECT id FROM usuarios WHERE email = 'autor@demo.invalid');
  u_ia   bigint := (SELECT id FROM usuarios WHERE email = 'agente-ia@demo.invalid');
  v_id   bigint;
  v2_id  bigint;
BEGIN
  INSERT INTO versoes (documento_id, maior, menor, autor_id, motivo, conteudo)
  VALUES ((SELECT id FROM documentos WHERE codigo = 'TS-POL-GER-001'), 0, 1, u_ia,
          'Criação', 'Texto fictício da política de segurança.')
  RETURNING id INTO v_id;
  PERFORM sgs_transicionar(v_id, 'em_revisao', u_rev, 'Enviado para revisão');
  PERFORM sgs_transicionar(v_id, 'aprovado',   u_resp, 'Aprovado');
  PERFORM sgs_transicionar(v_id, 'vigente',    u_resp, 'Entra em vigor', current_date - 350);

  -- PAE: v1.0 vigente e v2.0 em revisão (revisão após simulado fictício).
  INSERT INTO versoes (documento_id, maior, menor, autor_id, motivo, conteudo)
  VALUES ((SELECT id FROM documentos WHERE codigo = 'TS-PAE-TST-001'), 0, 1, u_aut,
          'Criação', 'Cenários fictícios: queda, afogamento, mal súbito.')
  RETURNING id INTO v_id;
  PERFORM sgs_transicionar(v_id, 'em_revisao', u_aut);
  PERFORM sgs_transicionar(v_id, 'aprovado',   u_resp);
  PERFORM sgs_transicionar(v_id, 'vigente',    u_resp, NULL, current_date - 60);

  v2_id := sgs_nova_versao(v_id, u_aut, 'Simulado fictício mostrou rota de evacuação desatualizada');
  UPDATE versoes SET resumo_mudancas = 'Nova rota de evacuação; contatos atualizados',
                     conteudo = 'Cenários fictícios: queda, afogamento, mal súbito. Nova rota de evacuação.'
   WHERE id = v2_id;
  PERFORM sgs_transicionar(v2_id, 'em_revisao', u_aut);

  -- Formulário: v1.0 vigente, com um registro gerado.
  INSERT INTO versoes (documento_id, maior, menor, autor_id, motivo, conteudo)
  VALUES ((SELECT id FROM documentos WHERE codigo = 'TS-FOR-TST-001'), 0, 1, u_aut,
          'Criação', 'Itens fictícios: equipamentos, clima, briefing, rádio.')
  RETURNING id INTO v_id;
  PERFORM sgs_transicionar(v_id, 'em_revisao', u_aut);
  PERFORM sgs_transicionar(v_id, 'aprovado',   u_resp);
  PERFORM sgs_transicionar(v_id, 'vigente',    u_resp);

  INSERT INTO registros (codigo, formulario_versao_id, roteiro_sigla, data, descricao, registrado_por)
  VALUES ('TS-REG-TST-001-' || to_char(current_date, 'YYYY-MM-DD'), v_id, 'TST', current_date,
          'Checklist fictício preenchido', (SELECT id FROM usuarios WHERE email = 'guia@demo.invalid'));
END $$;

-- Matriz: vínculos fictícios
INSERT INTO requisito_vinculos (requisito_id, documento_id, roteiro_sigla, justificativa, situacao, responsavel, proxima_acao)
VALUES
  ((SELECT id FROM requisitos WHERE capitulo = 5), (SELECT id FROM documentos WHERE codigo = 'TS-POL-GER-001'), NULL,
   'Aplicável: exemplo fictício', 'aprovado', 'Direção', 'Divulgar a política à equipe'),
  ((SELECT id FROM requisitos WHERE capitulo = 8), (SELECT id FROM documentos WHERE codigo = 'TS-PAE-TST-001'), 'TST',
   'Aplicável: exemplo fictício', 'aprovado', 'Coordenador de operação', 'Aprovar v2.0 e realizar novo simulado');

-- Ação fictícia atrasada
INSERT INTO acoes (origem, origem_referencia, descricao, prioridade, responsavel, prazo, roteiro_sigla, documento_id)
VALUES ('simulado', 'Simulado fictício', 'Atualizar rota de evacuação no PAE', 'alta', 'Coordenador de operação',
        current_date - 5, 'TST', (SELECT id FROM documentos WHERE codigo = 'TS-PAE-TST-001'));

INSERT INTO decisoes (descricao, decidido_por, decidido_em, contexto)
VALUES ('[DEMO] Aprovada a revisão do PAE após simulado', (SELECT id FROM usuarios WHERE email = 'responsavel@demo.invalid'),
        now(), 'Exemplo fictício');

COMMIT;
