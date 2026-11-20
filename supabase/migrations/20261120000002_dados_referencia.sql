BEGIN;
-- Itens do mapa da ISO 21101 (gerado a partir do index.html).
INSERT INTO public.itens_mapa (item, tipo, requisito, titulo, escopo, exigido_norma, ordem) VALUES
  ('d_contexto', 'documento', '4.1', 'Análise de Contexto da Empresa', 'empresa', false, 1),
  ('d_partes', 'documento', '4.2', 'Partes Interessadas e Requisitos', 'empresa', false, 2),
  ('d_escopo', 'documento', '4.3', 'Escopo do SGS', 'empresa', true, 3),
  ('d_politica', 'documento', '5.2', 'Política de Segurança', 'empresa', true, 4),
  ('d_funcoes', 'documento', '5.3', 'Quadro de Funções, Responsabilidades e Autoridades', 'empresa', false, 5),
  ('d_contexto_ativ', 'documento', '6.1.2', 'Contexto da Atividade (um por produto)', 'produto', true, 6),
  ('d_inventario', 'documento', '6.1.2', 'Inventário de Perigos e Riscos', 'produto', true, 7),
  ('d_legal', 'documento', '6.1.3', 'Lista de Requisitos Legais e Outros', 'empresa', false, 8),
  ('d_objetivos', 'documento', '6.2', 'Objetivos de Segurança e Plano de Ação', 'empresa', true, 9),
  ('d_matriz_comp', 'documento', '7.2', 'Matriz de Competências por Função', 'empresa', false, 10),
  ('d_com_equipe', 'documento', '7.4', 'Processo de Comunicação e Consulta com a Equipe', 'empresa', true, 11),
  ('d_com_part', 'documento', '7.4', 'Processo de Comunicação com Participantes', 'empresa', true, 12),
  ('d_termo', 'documento', '7.4', 'Termo de Conhecimento de Riscos e Corresponsabilidade', 'produto', false, 13),
  ('d_lista_mestra', 'documento', '7.5', 'Lista Mestra de Documentos e Registros', 'empresa', true, 14),
  ('d_proc_op', 'documento', '8.1', 'Procedimentos Operacionais por Atividade', 'produto', true, 15),
  ('d_equip', 'documento', '8.1', 'Procedimento de Manutenção e Controle de Equipamentos', 'empresa', true, 16),
  ('d_comp_part', 'documento', '8.1', 'Competência Mínima do Participante', 'produto', true, 17),
  ('d_pae', 'documento', '8.2', 'Plano de Atendimento a Emergências (PAE)', 'produto', true, 18),
  ('d_proc_inc', 'documento', '8.3', 'Procedimento de Gestão de Incidentes', 'empresa', true, 19),
  ('d_monit', 'documento', '9.1', 'Plano de Monitoramento e Indicadores', 'empresa', false, 20),
  ('d_prog_aud', 'documento', '9.2', 'Programa de Auditoria Interna', 'empresa', true, 21),
  ('d_lv_aud', 'documento', '9.2', 'Lista de Verificação da Auditoria', 'empresa', false, 22),
  ('r_competencia', 'registro', '7.2', 'Evidências de Competência', 'empresa', true, 23),
  ('r_treinamento', 'registro', '7.3', 'Registro de Treinamentos e Integração', 'empresa', false, 24),
  ('r_reuniao', 'registro', '7.4', 'Registro de Reuniões e Consultas com a Equipe', 'empresa', false, 25),
  ('r_ficha', 'registro', '8.2', 'Ficha do Participante', 'produto', true, 26),
  ('r_checklist', 'registro', '8.1', 'Check-lists e Registros de Equipamentos', 'produto', true, 27),
  ('r_teste', 'registro', '8.2', 'Registro de Testes e Simulados de Emergência', 'produto', true, 28),
  ('r_incidente', 'registro', '8.3', 'Registro de Incidentes', 'produto', true, 29),
  ('r_monit', 'registro', '9.1', 'Registro de Monitoramento do SGS', 'empresa', true, 30),
  ('r_feedback', 'registro', '9.1', 'Feedback dos Participantes', 'produto', false, 31),
  ('r_rel_aud', 'registro', '9.2', 'Relatório de Auditoria Interna', 'empresa', true, 32),
  ('r_ata', 'registro', '9.3', 'Ata de Análise Crítica pela Direção', 'empresa', true, 33),
  ('r_nc', 'registro', '10.1', 'Registro de Não Conformidade e Ação Corretiva', 'empresa', true, 34)
ON CONFLICT (item) DO UPDATE SET tipo = EXCLUDED.tipo, requisito = EXCLUDED.requisito, titulo = EXCLUDED.titulo,
  escopo = EXCLUDED.escopo, exigido_norma = EXCLUDED.exigido_norma, ordem = EXCLUDED.ordem;

-- Produto piloto (dado real informado por Vagner).
INSERT INTO public.produtos (id, nome, municipio, base, atividades, responsavel, situacao, descricao, piloto, ordem)
VALUES ('poco-de-ferro', 'Poço de Ferro', '', 'Recanto SOBRAGI', ARRAY['Rapel','Banho no poço','Escada de ferro'],
        'Vagner Fagundes', 'Em implantação',
        'Rapel e banho no poço, com subida pela escada de ferro. Roteiro piloto do SGS.', true, 1)
ON CONFLICT (id) DO NOTHING;

COMMIT;
