-- DADOS FICTÍCIOS para o ambiente de testes. Não aplicar em produção.
INSERT INTO public.produtos (id, nome, municipio, base, atividades, situacao, descricao, exemplo, ordem) VALUES
 ('exemplo-travessia', 'Travessia da Serra Azul', 'Exemplo – SC', 'Pousada Fictícia', ARRAY['Caminhada','Pernoite'],
  'Em implantação', 'Produto fictício para demonstração: travessia de dois dias com pernoite em abrigo.', true, 50),
 ('exemplo-cachoeirismo', 'Cachoeirismo do Vale Verde', 'Exemplo – RS', '', ARRAY['Cachoeirismo','Rapel'],
  'Em revisão', 'Produto fictício para demonstração: descida de cachoeiras com corda.', true, 51)
ON CONFLICT (id) DO NOTHING;
