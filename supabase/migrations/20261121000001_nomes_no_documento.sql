-- Nomes de quem criou, revisou e aprovou, para o rodapé dos documentos e o histórico de versões.
-- A tabela perfis só mostra o próprio perfil (ou todos, ao responsável); esta função devolve
-- apenas o nome (ou o e-mail, se não houver nome) e só para quem tem perfil ativo.
CREATE FUNCTION public.sgs_pessoas(p_ids uuid[])
RETURNS TABLE (id uuid, nome text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.id, coalesce(nullif(trim(p.nome), ''), p.email)
    FROM public.perfis p
   WHERE p.id = ANY (p_ids) AND public.sgs_papel() IS NOT NULL
$$;
REVOKE EXECUTE ON FUNCTION public.sgs_pessoas(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sgs_pessoas(uuid[]) TO authenticated;
