-- DADOS FICTÍCIOS para o ambiente de testes. Não aplicar em produção.
-- Uma empresa fictícia já liberada, com 2 produtos, para testar a separação entre empresas.
INSERT INTO public.empresas (id, nome, municipio, uf, situacao, liberada_em) VALUES
 ('00000000-0000-4000-8000-0000000000b0', 'Aventura Teste B (fictícia)', 'Exemplo', 'RS', 'ativa', now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.produtos (id, empresa_id, nome, municipio, base, atividades, situacao, descricao, exemplo, ordem) VALUES
 ('exemplo-b-travessia', '00000000-0000-4000-8000-0000000000b0', 'Travessia da Serra Azul', 'Exemplo – SC', 'Pousada Fictícia',
  ARRAY['Caminhada','Pernoite'], 'Em implantação', 'Produto fictício para demonstração: travessia de dois dias com pernoite em abrigo.', true, 50),
 ('exemplo-b-cachoeirismo', '00000000-0000-4000-8000-0000000000b0', 'Cachoeirismo do Vale Verde', 'Exemplo – RS', '',
  ARRAY['Cachoeirismo','Rapel'], 'Em revisão', 'Produto fictício para demonstração: descida de cachoeiras com corda.', true, 51)
ON CONFLICT (id) DO NOTHING;
