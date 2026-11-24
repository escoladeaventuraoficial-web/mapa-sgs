-- Liberação de usuários pela tela "Usuários" da plataforma (24/11/2026).
-- O responsável pelo SGS ativa, desativa e define o papel das pessoas que entraram com o e-mail.
-- Proteção nova: o sistema nunca fica sem um responsável ativo (ninguém tranca o SGS por engano).
CREATE OR REPLACE FUNCTION public.fn_protege_perfil() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF (NEW.papel, NEW.ativo, NEW.id) IS DISTINCT FROM (OLD.papel, OLD.ativo, OLD.id)
     AND coalesce(public.sgs_papel() <> 'admin_sgs', true)
     AND auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Só o responsável pelo SGS muda papel ou ativação de usuários';
  END IF;
  IF OLD.papel = 'admin_sgs' AND OLD.ativo
     AND NOT (NEW.papel = 'admin_sgs' AND NEW.ativo) THEN
    PERFORM pg_advisory_xact_lock(21101);
    IF NOT EXISTS (SELECT 1 FROM public.perfis
                    WHERE papel = 'admin_sgs' AND ativo AND id <> OLD.id) THEN
      RAISE EXCEPTION 'O SGS precisa de pelo menos um responsável ativo. Defina outro responsável antes de mudar este usuário.';
    END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.fn_protege_perfil() FROM PUBLIC, anon, authenticated;
