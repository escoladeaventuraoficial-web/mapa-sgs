-- Confere a migração da produção: tudo vira da Trilhas do Sul, nada se perde, Vagner continua Responsável.
\set ON_ERROR_STOP 1
\o /dev/null
DO $$
DECLARE ts uuid := '00000000-0000-4000-8000-000000000001';
BEGIN
  ASSERT (SELECT nome || situacao FROM empresas) = 'Trilhas do Sulativa', 'uma empresa, ativa';
  ASSERT (SELECT criada_por FROM empresas) = '00000000-0000-0000-0000-000000000001', 'criada por Vagner';
  ASSERT (SELECT admin_plataforma FROM perfis), 'Vagner é admin da plataforma';
  ASSERT (SELECT papel::text || ativo FROM membros) = 'admin_sgstrue', 'Vagner Responsável da Trilhas';
  ASSERT NOT EXISTS (SELECT 1 FROM produtos WHERE empresa_id IS DISTINCT FROM ts), 'produtos';
  ASSERT NOT EXISTS (SELECT 1 FROM documentos WHERE empresa_id IS DISTINCT FROM ts), 'documentos';
  ASSERT NOT EXISTS (SELECT 1 FROM versoes WHERE empresa_id IS DISTINCT FROM ts), 'versões';
  ASSERT NOT EXISTS (SELECT 1 FROM transicoes_versao WHERE empresa_id IS DISTINCT FROM ts), 'histórico';
  ASSERT NOT EXISTS (SELECT 1 FROM progresso_itens WHERE empresa_id IS DISTINCT FROM ts), 'progresso';
  ASSERT (SELECT count(*) FROM produtos) = 5 AND (SELECT count(*) FROM produtos WHERE NOT arquivado) = 3, 'fictícios arquivados, nada apagado';
  ASSERT (SELECT conteudo FROM versoes) = '{"itens":[1,2,3]}'::jsonb, 'rascunho preservado';
  ASSERT (SELECT count(*) FROM transicoes_versao) = (SELECT tr FROM _antes), 'transições preservadas';
  ASSERT (SELECT count(*) FROM auditoria) >= (SELECT aud FROM _antes), 'auditoria preservada';
  ASSERT (SELECT count(*) FROM assinaturas) = 1, 'assinatura preservada';
END $$;
-- Vagner continua trabalhando como antes (o site atual não manda empresa_id: usa a empresa padrão).
SET ROLE authenticated;
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM produtos WHERE NOT arquivado) = 3, 'Vagner vê os produtos';
  ASSERT (SELECT count(*) FROM versoes) = 1, 'Vagner vê o rascunho';
END $$;
UPDATE versoes SET conteudo = '{"itens":[1,2,3,4]}';
INSERT INTO produtos (id, nome) VALUES ('novo-teste', 'Novo Teste');
SELECT sgs_marcar_item('d_politica', NULL, true);
SELECT sgs_transicionar(1, 'em_revisao');
RESET ROLE;
DROP TABLE _antes;
\o
\echo 'Migração da Trilhas do Sul conferida.'
