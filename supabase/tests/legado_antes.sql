-- Simula a produção antes da migração multi-empresa: Vagner Responsável, Poço de Ferro,
-- 2 produtos reais, 2 fictícios, rascunho do 4.1 com histórico e assinatura.
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
 ('00000000-0000-0000-0000-000000000001', 'vagner@exemplo.invalid', '{"name":"Vagner Teste"}');
INSERT INTO public.produtos (id, nome, ordem) VALUES ('caminhos-teste', 'Caminhos Teste', 2), ('vale-teste', 'Vale Teste', 3);
INSERT INTO public.produtos (id, nome, exemplo, ordem) VALUES ('exemplo-travessia', 'Travessia', true, 50), ('exemplo-cachoeirismo', 'Cachoeirismo', true, 51);
SET ROLE authenticated;
SET request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
INSERT INTO public.documentos (requisito, titulo, item) VALUES ('4.1', 'Contexto da Organização', 'd_contexto');
INSERT INTO public.versoes (documento_id, conteudo) SELECT id, '{"itens":[1,2,3]}' FROM public.documentos;
SELECT public.sgs_marcar_item('d_pae', 'poco-de-ferro', true);
INSERT INTO public.assinaturas (perfil_id, imagem) VALUES (auth.uid(), 'data:image/png;base64,VV');
RESET ROLE;
CREATE TABLE public._antes AS SELECT (SELECT count(*) FROM public.auditoria) aud, (SELECT count(*) FROM public.transicoes_versao) tr;
