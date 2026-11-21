-- Assinatura de cada usuário (imagem PNG), usada no rodapé dos documentos que ele revisou ou aprovou.
-- Fica no banco, protegida por RLS: só quem tem perfil ativo vê; cada um grava só a própria.
CREATE TABLE public.assinaturas (
  perfil_id     uuid PRIMARY KEY REFERENCES public.perfis(id),
  imagem        text NOT NULL CHECK (imagem LIKE 'data:image/png;base64,%' AND length(imagem) < 400000),
  atualizado_em timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_toca BEFORE UPDATE ON public.assinaturas
  FOR EACH ROW EXECUTE FUNCTION public.fn_toca_atualizado();
CREATE TRIGGER trg_auditoria AFTER INSERT OR UPDATE OR DELETE ON public.assinaturas
  FOR EACH ROW EXECUTE FUNCTION public.fn_auditoria();

ALTER TABLE public.assinaturas ENABLE ROW LEVEL SECURITY;
CREATE POLICY ler ON public.assinaturas FOR SELECT TO authenticated
  USING (public.sgs_papel() IS NOT NULL);
CREATE POLICY incluir ON public.assinaturas FOR INSERT TO authenticated
  WITH CHECK (perfil_id = auth.uid() AND public.sgs_papel() IS NOT NULL);
CREATE POLICY editar ON public.assinaturas FOR UPDATE TO authenticated
  USING (perfil_id = auth.uid() AND public.sgs_papel() IS NOT NULL)
  WITH CHECK (perfil_id = auth.uid());

REVOKE ALL ON public.assinaturas FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.assinaturas TO authenticated;
