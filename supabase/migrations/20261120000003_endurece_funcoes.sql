-- Recomendações do verificador de segurança do Supabase.
BEGIN;
ALTER FUNCTION public.fn_toca_atualizado() SET search_path = public;
ALTER FUNCTION public.fn_somente_inclusao() SET search_path = public;
-- Funções de gatilho não são chamadas pela API.
REVOKE EXECUTE ON FUNCTION public.fn_auditoria(), public.fn_novo_usuario(), public.fn_protege_perfil(),
  public.fn_versao_criada(), public.fn_valida_escopo(), public.fn_protege_versao(),
  public.fn_toca_atualizado(), public.fn_somente_inclusao() FROM PUBLIC, anon, authenticated;
-- Usadas pelas políticas de RLS: só para quem está logado (retornam apenas o papel do próprio usuário).
REVOKE EXECUTE ON FUNCTION public.sgs_papel(), public.sgs_pode_editar() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sgs_papel(), public.sgs_pode_editar() TO authenticated;
COMMIT;
