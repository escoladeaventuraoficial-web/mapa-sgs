-- Dados de referência do padrão TS-PG-GER-001 (não contêm dados operacionais).
BEGIN;

INSERT INTO tipos_documento (sigla, nome, descricao, escopo_usual) VALUES
  ('MAN', 'Manual', 'Manual do SGS: escopo, estrutura, mapa dos documentos', 'GER'),
  ('POL', 'Política', 'Política de segurança e compromissos da direção', 'GER'),
  ('PG',  'Procedimento de gestão', 'Como o SGS funciona: documentos, auditoria, ações corretivas, análise crítica', 'GER'),
  ('PO',  'Procedimento operacional', 'Como a atividade é conduzida em campo', 'Roteiro'),
  ('IT',  'Instrução de trabalho', 'Passo a passo de uma tarefa específica', 'Roteiro ou GER'),
  ('AR',  'Inventário de perigos e avaliação de riscos', 'Perigos, riscos, controles e risco residual', 'Roteiro'),
  ('PAE', 'Plano de Atendimento a Emergências', 'Cenários, responsabilidades, contatos, rotas de evacuação', 'Roteiro'),
  ('PLA', 'Plano', 'Objetivos, programa de simulados, de auditorias, de capacitação', 'GER'),
  ('FOR', 'Formulário / modelo', 'Modelo em branco a ser preenchido', 'Roteiro ou GER'),
  ('REG', 'Registro', 'Formulário preenchido; evidência datada, sem versões', 'Roteiro ou GER'),
  ('INF', 'Informação ao participante', 'Briefing, termo de conhecimento de riscos, orientações', 'Roteiro'),
  ('LIS', 'Lista', 'Lista mestra, requisitos legais, fornecedores, equipamentos', 'GER')
ON CONFLICT (sigla) DO NOTHING;

INSERT INTO roteiros (sigla, nome, descricao) VALUES
  ('PDF', 'Poço de Ferro', 'Roteiro piloto do SGS')
ON CONFLICT (sigla) DO NOTHING;

-- Temas por capítulo (estrutura de alto nível). A cláusula exata fica em branco
-- até ser verificada no texto autorizado da ABNT NBR ISO 21101:2014 + Emenda 1:2024.
INSERT INTO requisitos (capitulo, tema, descricao)
SELECT * FROM (VALUES
  (4,  'Contexto da organização', 'Questões internas e externas (incluindo a relevância das mudanças climáticas), partes interessadas e seus requisitos, escopo do SGS'),
  (5,  'Liderança', 'Comprometimento da direção, política de segurança, papéis, responsabilidades e autoridades'),
  (6,  'Planejamento', 'Ações para abordar riscos e oportunidades, objetivos de segurança e planejamento para alcançá-los'),
  (7,  'Apoio', 'Recursos, competência, conscientização, comunicação, informação documentada, informação aos participantes'),
  (8,  'Operação', 'Planejamento e controle operacional, fornecedores, preparação e resposta a emergências'),
  (9,  'Avaliação de desempenho', 'Monitoramento, medição, análise e avaliação, auditoria interna, análise crítica pela direção'),
  (10, 'Melhoria', 'Incidentes, quase acidentes, não conformidades, ação corretiva, melhoria contínua')
) AS t(capitulo, tema, descricao)
WHERE NOT EXISTS (SELECT 1 FROM requisitos r WHERE r.capitulo = t.capitulo AND r.tema = t.tema);

COMMIT;
