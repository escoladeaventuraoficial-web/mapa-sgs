-- Plataforma multi-empresa (plano aprovado por Vagner em 24/11/2026).
--
-- Regras:
--  * Cada empresa tem o seu SGS. Nenhuma empresa lê ou altera dados de outra (RLS por empresa_id).
--  * Quem cria uma empresa vira Responsável pelo SGS dela. A empresa nasce "aguardando" e só
--    funciona depois que o administrador da plataforma (Vagner) libera (decisão de 24/11/2026).
--  * O papel (Responsável, Aprovador, Autor...) passa a ser por empresa (tabela membros).
--    As colunas perfis.papel e perfis.ativo ficam congeladas, só como histórico.
--  * A equipe entra por convite: e-mail + papel. Quem entra sem convite não cai em nenhuma empresa.
--  * O administrador da plataforma vê a lista de empresas, mas não os documentos delas.
--  * Tudo o que já existe vira da empresa "Trilhas do Sul". Nada é apagado.
--  * Os 2 produtos fictícios de exemplo são arquivados.

BEGIN;

-- ---------------------------------------------------------------------------
-- Empresas, membros e convites
-- ---------------------------------------------------------------------------
CREATE TYPE public.situacao_empresa AS ENUM ('aguardando', 'ativa', 'suspensa');

CREATE TABLE public.empresas (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome          text NOT NULL CHECK (length(trim(nome)) BETWEEN 2 AND 120),
  cnpj          text CHECK (cnpj IS NULL OR cnpj ~ '^[0-9]{14}$'),
  municipio     text NOT NULL DEFAULT '',
  uf            text NOT NULL DEFAULT '' CHECK (uf = '' OR uf ~ '^[A-Z]{2}$'),
  logo_path     text,
  situacao      public.situacao_empresa NOT NULL DEFAULT 'aguardando',
  criada_por    uuid REFERENCES public.perfis(id),
  criada_em     timestamptz NOT NULL DEFAULT now(),
  liberada_por  uuid REFERENCES public.perfis(id),
  liberada_em   timestamptz,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX empresas_cnpj_unico ON public.empresas (cnpj) WHERE cnpj IS NOT NULL;

CREATE TABLE public.membros (
  empresa_id uuid NOT NULL REFERENCES public.empresas(id),
  perfil_id  uuid NOT NULL REFERENCES public.perfis(id),
  papel      public.papel_usuario NOT NULL DEFAULT 'leitura',
  ativo      boolean NOT NULL DEFAULT true,
  criado_em  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (empresa_id, perfil_id)
);
CREATE INDEX membros_perfil ON public.membros (perfil_id);

CREATE TABLE public.convites (
  id            bigserial PRIMARY KEY,
  empresa_id    uuid NOT NULL REFERENCES public.empresas(id),
  email         text NOT NULL CHECK (email = lower(trim(email)) AND email LIKE '%_@_%'),
  papel         public.papel_usuario NOT NULL CHECK (papel <> 'agente_ia'),
  convidado_por uuid NOT NULL REFERENCES public.perfis(id),
  criado_em     timestamptz NOT NULL DEFAULT now(),
  expira_em     timestamptz NOT NULL DEFAULT now() + interval '14 days',
  aceito_em     timestamptz,
  aceito_por    uuid REFERENCES public.perfis(id)
);
CREATE UNIQUE INDEX convites_pendente_unico ON public.convites (empresa_id, email) WHERE aceito_em IS NULL;

-- Administrador da plataforma: só muda pelo painel do Supabase (service role), nunca pelo site.
ALTER TABLE public.perfis ADD COLUMN admin_plataforma boolean NOT NULL DEFAULT false;

-- ---------------------------------------------------------------------------
-- Funções de acesso
-- ---------------------------------------------------------------------------
-- Papel do usuário logado na empresa (NULL se não for membro ativo ou se a empresa não estiver ativa).
CREATE FUNCTION public.sgs_papel(p_empresa uuid) RETURNS public.papel_usuario
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT m.papel FROM public.membros m JOIN public.empresas e ON e.id = m.empresa_id
   WHERE m.empresa_id = p_empresa AND m.perfil_id = auth.uid() AND m.ativo AND e.situacao = 'ativa'
$$;

CREATE FUNCTION public.sgs_pode_editar(p_empresa uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(public.sgs_papel(p_empresa) IN ('admin_sgs', 'aprovador', 'revisor', 'autor'), false)
$$;

CREATE FUNCTION public.sgs_admin_plataforma() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT admin_plataforma FROM public.perfis WHERE id = auth.uid()), false)
$$;

-- Empresa usada quando o registro não informa empresa_id: a única empresa ativa do usuário.
-- Com mais de uma empresa, o site precisa informar qual (senão o NOT NULL recusa).
CREATE FUNCTION public.sgs_empresa_padrao() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN count(*) = 1 THEN min(m.empresa_id::text)::uuid END
    FROM public.membros m JOIN public.empresas e ON e.id = m.empresa_id
   WHERE m.perfil_id = auth.uid() AND m.ativo AND e.situacao = 'ativa'
$$;

-- Funções antigas (sem empresa) passam a responder pela empresa padrão do usuário.
CREATE OR REPLACE FUNCTION public.sgs_papel() RETURNS public.papel_usuario
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.sgs_papel(public.sgs_empresa_padrao())
$$;
CREATE OR REPLACE FUNCTION public.sgs_pode_editar() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.sgs_pode_editar(public.sgs_empresa_padrao())
$$;

-- ---------------------------------------------------------------------------
-- Trilhas do Sul: primeira empresa, dona de tudo o que já existe
-- ---------------------------------------------------------------------------
INSERT INTO public.empresas (id, nome, municipio, uf, logo_path, situacao, criada_por, liberada_em)
SELECT '00000000-0000-4000-8000-000000000001', 'Trilhas do Sul', '', 'SC', 'img/logo-trilhas-do-sul.png', 'ativa',
       (SELECT id FROM public.perfis WHERE papel = 'admin_sgs' AND ativo ORDER BY criado_em LIMIT 1), now();

INSERT INTO public.membros (empresa_id, perfil_id, papel, ativo, criado_em)
SELECT '00000000-0000-4000-8000-000000000001', id, papel, ativo, criado_em FROM public.perfis;

UPDATE public.perfis SET admin_plataforma = true
 WHERE id = (SELECT criada_por FROM public.empresas WHERE id = '00000000-0000-4000-8000-000000000001');

-- ---------------------------------------------------------------------------
-- empresa_id nas tabelas do SGS
-- ---------------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['produtos','progresso_itens','documentos','versoes','transicoes_versao','decisoes'] LOOP
    -- Os gatilhos de proteção do histórico ficam desligados só durante o preenchimento.
    EXECUTE format('ALTER TABLE public.%I DISABLE TRIGGER USER', t);
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN empresa_id uuid REFERENCES public.empresas(id)', t);
    EXECUTE format('UPDATE public.%I SET empresa_id = %L', t, '00000000-0000-4000-8000-000000000001');
    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN empresa_id SET NOT NULL', t);
    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN empresa_id SET DEFAULT public.sgs_empresa_padrao()', t);
    EXECUTE format('CREATE INDEX %I ON public.%I (empresa_id)', t || '_empresa', t);
    EXECUTE format('ALTER TABLE public.%I ENABLE TRIGGER USER', t);
  END LOOP;
END $$;

ALTER TABLE public.auditoria ADD COLUMN empresa_id uuid;
ALTER TABLE public.auditoria DISABLE TRIGGER USER;
UPDATE public.auditoria SET empresa_id = '00000000-0000-4000-8000-000000000001';
ALTER TABLE public.auditoria ENABLE TRIGGER USER;
CREATE INDEX auditoria_empresa ON public.auditoria (empresa_id);

-- Produtos fictícios de exemplo saem da tela (ficam no histórico).
UPDATE public.produtos SET arquivado = true WHERE exemplo;

-- Unicidade passa a ser dentro da empresa.
DROP INDEX public.produtos_nome_unico;
CREATE UNIQUE INDEX produtos_nome_unico ON public.produtos (empresa_id, lower(nome)) WHERE NOT arquivado;
DROP INDEX public.progresso_unico;
CREATE UNIQUE INDEX progresso_unico ON public.progresso_itens (empresa_id, item, coalesce(produto_id, ''));
DROP INDEX public.documentos_unicos;
CREATE UNIQUE INDEX documentos_unicos
  ON public.documentos (empresa_id, requisito, coalesce(produto_id, ''), lower(coalesce(assunto, '')));

-- ---------------------------------------------------------------------------
-- Coerência: o registro é da mesma empresa do produto / documento / versão
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.fn_empresa_do_pai() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_emp uuid; v_novo jsonb := to_jsonb(NEW);
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.empresa_id IS DISTINCT FROM OLD.empresa_id THEN
    RAISE EXCEPTION 'Um registro não muda de empresa';
  END IF;
  IF TG_TABLE_NAME = 'versoes' THEN
    SELECT empresa_id INTO v_emp FROM public.documentos WHERE id = NEW.documento_id;
  ELSIF TG_TABLE_NAME = 'transicoes_versao' THEN
    SELECT empresa_id INTO v_emp FROM public.versoes WHERE id = NEW.versao_id;
  ELSIF v_novo->>'produto_id' IS NOT NULL THEN
    SELECT empresa_id INTO v_emp FROM public.produtos WHERE id = v_novo->>'produto_id';
  END IF;
  IF v_emp IS NOT NULL THEN
    IF TG_OP = 'INSERT' AND NEW.empresa_id IS NOT NULL AND NEW.empresa_id <> v_emp
       AND NEW.empresa_id IS DISTINCT FROM public.sgs_empresa_padrao() THEN
      RAISE EXCEPTION 'O registro e o seu produto/documento são de empresas diferentes';
    END IF;
    NEW.empresa_id := v_emp;
  END IF;
  IF NEW.empresa_id IS NULL THEN
    RAISE EXCEPTION 'Informe a empresa do registro';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_empresa BEFORE INSERT OR UPDATE ON public.progresso_itens
  FOR EACH ROW EXECUTE FUNCTION public.fn_empresa_do_pai();
CREATE TRIGGER trg_empresa BEFORE INSERT OR UPDATE ON public.documentos
  FOR EACH ROW EXECUTE FUNCTION public.fn_empresa_do_pai();
CREATE TRIGGER trg_empresa BEFORE INSERT OR UPDATE ON public.versoes
  FOR EACH ROW EXECUTE FUNCTION public.fn_empresa_do_pai();
CREATE TRIGGER trg_empresa BEFORE INSERT ON public.transicoes_versao
  FOR EACH ROW EXECUTE FUNCTION public.fn_empresa_do_pai();
CREATE TRIGGER trg_empresa BEFORE INSERT OR UPDATE ON public.decisoes
  FOR EACH ROW EXECUTE FUNCTION public.fn_empresa_do_pai();
CREATE TRIGGER trg_empresa BEFORE INSERT OR UPDATE ON public.produtos
  FOR EACH ROW EXECUTE FUNCTION public.fn_empresa_do_pai();

-- Auditoria registra a empresa do registro alterado.
CREATE OR REPLACE FUNCTION public.fn_auditoria() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_antes  jsonb := CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END;
  v_depois jsonb := CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END;
  v_emp    uuid;
BEGIN
  v_emp := CASE WHEN TG_TABLE_NAME = 'empresas' THEN coalesce(v_depois, v_antes)->>'id'
                ELSE coalesce(v_depois, v_antes)->>'empresa_id' END;
  INSERT INTO public.auditoria (tabela, registro_id, operacao, dados_antes, dados_depois, usuario_id, empresa_id)
  VALUES (TG_TABLE_NAME, coalesce(v_depois->>'id', v_antes->>'id', v_depois->>'perfil_id', v_antes->>'perfil_id'),
          TG_OP, v_antes, v_depois, auth.uid(), v_emp);
  RETURN NULL;
END $$;
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['empresas','membros','convites'] LOOP
    EXECUTE format('CREATE TRIGGER trg_auditoria AFTER INSERT OR UPDATE OR DELETE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.fn_auditoria()', t);
  END LOOP;
END $$;
CREATE TRIGGER trg_toca BEFORE UPDATE ON public.empresas
  FOR EACH ROW EXECUTE FUNCTION public.fn_toca_atualizado();
CREATE TRIGGER trg_sem_exclusao BEFORE DELETE ON public.empresas
  FOR EACH ROW EXECUTE FUNCTION public.fn_somente_inclusao();

-- ---------------------------------------------------------------------------
-- Proteções de empresas, membros e perfis
-- ---------------------------------------------------------------------------
-- Situação e liberação da empresa só mudam pelo administrador da plataforma.
CREATE FUNCTION public.fn_protege_empresa() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND coalesce(current_setting('sgs.admin_plataforma', true), '') <> 'on'
     AND (NEW.situacao, NEW.liberada_por, NEW.liberada_em, NEW.criada_por, NEW.criada_em)
         IS DISTINCT FROM (OLD.situacao, OLD.liberada_por, OLD.liberada_em, OLD.criada_por, OLD.criada_em) THEN
    RAISE EXCEPTION 'Só o administrador da plataforma libera ou suspende empresas';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_protege_empresa BEFORE UPDATE ON public.empresas
  FOR EACH ROW EXECUTE FUNCTION public.fn_protege_empresa();

-- Membros: só o Responsável da empresa muda papel e ativação; a empresa nunca fica sem Responsável ativo.
CREATE FUNCTION public.fn_protege_membro() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF (NEW.empresa_id, NEW.perfil_id) IS DISTINCT FROM (OLD.empresa_id, OLD.perfil_id) THEN
    RAISE EXCEPTION 'Um vínculo não muda de empresa nem de pessoa';
  END IF;
  IF auth.uid() IS NOT NULL AND (NEW.papel, NEW.ativo) IS DISTINCT FROM (OLD.papel, OLD.ativo)
     AND coalesce(public.sgs_papel(OLD.empresa_id) <> 'admin_sgs', true) THEN
    RAISE EXCEPTION 'Só o responsável pelo SGS da empresa muda papel ou ativação de usuários';
  END IF;
  IF OLD.papel = 'admin_sgs' AND OLD.ativo AND NOT (NEW.papel = 'admin_sgs' AND NEW.ativo) THEN
    PERFORM pg_advisory_xact_lock(21101, hashtext(OLD.empresa_id::text));
    IF NOT EXISTS (SELECT 1 FROM public.membros
                    WHERE empresa_id = OLD.empresa_id AND papel = 'admin_sgs' AND ativo
                      AND perfil_id <> OLD.perfil_id) THEN
      RAISE EXCEPTION 'O SGS precisa de pelo menos um responsável ativo. Defina outro responsável antes de mudar este usuário.';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_protege_membro BEFORE UPDATE ON public.membros
  FOR EACH ROW EXECUTE FUNCTION public.fn_protege_membro();

-- Perfis: cada um muda o próprio nome. Papel, ativação e admin_plataforma ficam congelados para o site.
CREATE OR REPLACE FUNCTION public.fn_protege_perfil() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NOT NULL
     AND (NEW.papel, NEW.ativo, NEW.id, NEW.admin_plataforma, NEW.email)
         IS DISTINCT FROM (OLD.papel, OLD.ativo, OLD.id, OLD.admin_plataforma, OLD.email) THEN
    RAISE EXCEPTION 'O papel agora é definido por empresa, na tela Usuários';
  END IF;
  RETURN NEW;
END $$;

-- Aceita os convites pendentes para o e-mail da pessoa (chamado no cadastro e a cada login).
CREATE FUNCTION public.fn_aceitar_convites(p_perfil uuid, p_email text) RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c record; n int := 0;
BEGIN
  FOR c IN SELECT * FROM public.convites
            WHERE email = lower(trim(p_email)) AND aceito_em IS NULL AND expira_em > now()
            FOR UPDATE LOOP
    INSERT INTO public.membros (empresa_id, perfil_id, papel, ativo)
    VALUES (c.empresa_id, p_perfil, c.papel, true)
    ON CONFLICT (empresa_id, perfil_id) DO NOTHING;
    UPDATE public.convites SET aceito_em = now(), aceito_por = p_perfil WHERE id = c.id;
    n := n + 1;
  END LOOP;
  RETURN n;
END $$;

-- Novo login: perfil sem empresa. Em banco novo (sem ninguém), o primeiro vira administrador da
-- plataforma e Responsável da empresa fundadora.
CREATE OR REPLACE FUNCTION public.fn_novo_usuario() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_primeiro boolean;
BEGIN
  PERFORM pg_advisory_xact_lock(21101);
  SELECT NOT EXISTS (SELECT 1 FROM public.perfis) INTO v_primeiro;
  INSERT INTO public.perfis (id, nome, email, papel, ativo, admin_plataforma)
  VALUES (NEW.id, coalesce(NEW.raw_user_meta_data->>'name', NEW.raw_user_meta_data->>'full_name', ''),
          lower(NEW.email), 'leitura', false, v_primeiro);
  IF v_primeiro THEN
    INSERT INTO public.membros (empresa_id, perfil_id, papel, ativo)
    SELECT id, NEW.id, 'admin_sgs', true FROM public.empresas ORDER BY criada_em LIMIT 1;
    UPDATE public.empresas SET criada_por = NEW.id
     WHERE id = (SELECT id FROM public.empresas ORDER BY criada_em LIMIT 1) AND criada_por IS NULL;
  END IF;
  IF NEW.email IS NOT NULL THEN
    PERFORM public.fn_aceitar_convites(NEW.id, NEW.email);
  END IF;
  RETURN NEW;
END $$;

-- ---------------------------------------------------------------------------
-- Ações do site (RPC)
-- ---------------------------------------------------------------------------
-- "Criar minha empresa": quem cria vira Responsável; a empresa aguarda a liberação.
CREATE FUNCTION public.sgs_criar_empresa(p_nome text, p_cnpj text DEFAULT NULL,
                                         p_municipio text DEFAULT '', p_uf text DEFAULT '',
                                         p_nome_pessoa text DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_id uuid;
BEGIN
  IF v_uid IS NULL OR NOT EXISTS (SELECT 1 FROM public.perfis WHERE id = v_uid) THEN
    RAISE EXCEPTION 'Entre com o seu e-mail antes de criar uma empresa';
  END IF;
  IF EXISTS (SELECT 1 FROM public.empresas WHERE criada_por = v_uid AND situacao = 'aguardando') THEN
    RAISE EXCEPTION 'Você já tem uma empresa aguardando liberação';
  END IF;
  IF (SELECT count(*) FROM public.empresas WHERE criada_por = v_uid) >= 3 THEN
    RAISE EXCEPTION 'Limite de empresas criadas por pessoa atingido. Fale com o administrador da plataforma.';
  END IF;
  INSERT INTO public.empresas (nome, cnpj, municipio, uf, criada_por)
  VALUES (trim(p_nome), nullif(regexp_replace(coalesce(p_cnpj, ''), '[^0-9]', '', 'g'), ''),
          trim(coalesce(p_municipio, '')), upper(trim(coalesce(p_uf, ''))), v_uid)
  RETURNING id INTO v_id;
  INSERT INTO public.membros (empresa_id, perfil_id, papel, ativo) VALUES (v_id, v_uid, 'admin_sgs', true);
  IF nullif(trim(coalesce(p_nome_pessoa, '')), '') IS NOT NULL THEN
    UPDATE public.perfis SET nome = trim(p_nome_pessoa) WHERE id = v_uid AND nome = '';
  END IF;
  RETURN v_id;
END $$;

-- Administrador da plataforma: lista de empresas (sem documentos).
CREATE FUNCTION public.sgs_admin_empresas()
RETURNS TABLE (id uuid, nome text, cnpj text, municipio text, uf text, situacao public.situacao_empresa,
               criada_em timestamptz, liberada_em timestamptz, responsavel_email text, usuarios bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.sgs_admin_plataforma() THEN
    RAISE EXCEPTION 'Só o administrador da plataforma vê a lista de empresas';
  END IF;
  RETURN QUERY
  SELECT e.id, e.nome, e.cnpj, e.municipio, e.uf, e.situacao, e.criada_em, e.liberada_em,
         (SELECT p.email FROM public.perfis p WHERE p.id = e.criada_por),
         (SELECT count(*) FROM public.membros m WHERE m.empresa_id = e.id AND m.ativo)
    FROM public.empresas e ORDER BY e.situacao, e.criada_em;
END $$;

-- Administrador da plataforma: liberar ou suspender uma empresa.
CREATE FUNCTION public.sgs_definir_situacao_empresa(p_empresa uuid, p_situacao public.situacao_empresa)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.sgs_admin_plataforma() THEN
    RAISE EXCEPTION 'Só o administrador da plataforma libera ou suspende empresas';
  END IF;
  PERFORM set_config('sgs.admin_plataforma', 'on', true);
  UPDATE public.empresas
     SET situacao = p_situacao,
         liberada_por = CASE WHEN p_situacao = 'ativa' THEN auth.uid() ELSE liberada_por END,
         liberada_em  = CASE WHEN p_situacao = 'ativa' THEN now() ELSE liberada_em END
   WHERE id = p_empresa;
  IF NOT FOUND THEN RAISE EXCEPTION 'Empresa não encontrada'; END IF;
  PERFORM set_config('sgs.admin_plataforma', 'off', true);
END $$;

-- Responsável convida alguém pelo e-mail. Se a pessoa já tem login, entra na hora.
CREATE FUNCTION public.sgs_convidar(p_empresa uuid, p_email text, p_papel public.papel_usuario)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_email text := lower(trim(p_email)); v_id bigint; v_perfil uuid;
BEGIN
  IF public.sgs_papel(p_empresa) IS DISTINCT FROM 'admin_sgs' THEN
    RAISE EXCEPTION 'Só o responsável pelo SGS da empresa convida pessoas';
  END IF;
  IF p_papel = 'agente_ia' THEN RAISE EXCEPTION 'O papel Agente de IA não é dado por convite'; END IF;
  SELECT id INTO v_perfil FROM public.perfis WHERE lower(email) = v_email;
  IF v_perfil IS NOT NULL AND EXISTS (SELECT 1 FROM public.membros WHERE empresa_id = p_empresa AND perfil_id = v_perfil) THEN
    RAISE EXCEPTION 'Esta pessoa já faz parte da empresa; mude o papel na lista de usuários';
  END IF;
  INSERT INTO public.convites (empresa_id, email, papel, convidado_por)
  VALUES (p_empresa, v_email, p_papel, auth.uid())
  ON CONFLICT (empresa_id, email) WHERE aceito_em IS NULL
  DO UPDATE SET papel = EXCLUDED.papel, convidado_por = EXCLUDED.convidado_por,
                criado_em = now(), expira_em = now() + interval '14 days'
  RETURNING id INTO v_id;
  IF v_perfil IS NOT NULL THEN
    PERFORM public.fn_aceitar_convites(v_perfil, v_email);
  END IF;
  RETURN v_id;
END $$;

-- O site chama a cada login: aceita convites feitos depois do cadastro da pessoa.
CREATE FUNCTION public.sgs_aceitar_convites() RETURNS int
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT public.fn_aceitar_convites(id, email) FROM public.perfis WHERE id = auth.uid() AND email IS NOT NULL
$$;

-- Marcar item: versão com empresa (a antiga, sem empresa, usa a empresa padrão).
CREATE FUNCTION public.sgs_marcar_item(p_empresa uuid, p_item text, p_produto text, p_pronto boolean) RETURNS void
LANGUAGE sql SECURITY INVOKER SET search_path = public AS $$
  INSERT INTO public.progresso_itens (empresa_id, item, produto_id, pronto)
  VALUES (p_empresa, p_item, p_produto, p_pronto)
  ON CONFLICT (empresa_id, item, (coalesce(produto_id, ''))) DO UPDATE SET pronto = EXCLUDED.pronto
$$;
CREATE OR REPLACE FUNCTION public.sgs_marcar_item(p_item text, p_produto text, p_pronto boolean) RETURNS void
LANGUAGE sql SECURITY INVOKER SET search_path = public AS $$
  SELECT public.sgs_marcar_item(
    coalesce((SELECT empresa_id FROM public.produtos WHERE id = p_produto), public.sgs_empresa_padrao()),
    p_item, p_produto, p_pronto)
$$;

-- Nomes no rodapé: só de pessoas que estão numa empresa ativa em comum com quem pergunta.
CREATE OR REPLACE FUNCTION public.sgs_pessoas(p_ids uuid[])
RETURNS TABLE (id uuid, nome text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT DISTINCT p.id, coalesce(nullif(trim(p.nome), ''), p.email)
    FROM public.perfis p
    JOIN public.membros m  ON m.perfil_id = p.id
    JOIN public.membros eu ON eu.empresa_id = m.empresa_id AND eu.perfil_id = auth.uid() AND eu.ativo
   WHERE p.id = ANY (p_ids) AND public.sgs_papel(m.empresa_id) IS NOT NULL
$$;

-- ---------------------------------------------------------------------------
-- Fluxo de aprovação: papel conferido na empresa do documento
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sgs_transicionar(
  p_versao_id  bigint,
  p_para       public.estado_versao,
  p_comentario text DEFAULT NULL,
  p_vigencia   date DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v       public.versoes%ROWTYPE;
  v_ant   public.versoes%ROWTYPE;
  v_papel public.papel_usuario;
  v_uid   uuid := auth.uid();
  v_ok    boolean;
  v_primeira boolean;
BEGIN
  SELECT * INTO v FROM public.versoes WHERE id = p_versao_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Versão % não encontrada', p_versao_id; END IF;
  v_papel := public.sgs_papel(v.empresa_id);
  IF v_papel IS NULL THEN RAISE EXCEPTION 'Versão % não encontrada', p_versao_id; END IF;
  IF v_papel IN ('agente_ia', 'equipe_campo', 'leitura') THEN
    RAISE EXCEPTION 'O papel % não pode mudar o estado de versões', v_papel;
  END IF;

  v_ok := CASE
    WHEN v.estado = 'rascunho'   AND p_para = 'em_revisao' THEN v_papel IN ('autor','revisor','aprovador','admin_sgs')
    WHEN v.estado = 'em_revisao' AND p_para = 'rascunho'   THEN v_papel IN ('revisor','aprovador','admin_sgs')
    WHEN v.estado = 'em_revisao' AND p_para = 'aprovado'   THEN v_papel IN ('aprovador','admin_sgs')
    WHEN v.estado = 'aprovado'   AND p_para = 'vigente'    THEN v_papel IN ('aprovador','admin_sgs')
    WHEN v.estado IN ('vigente','substituido','aprovado') AND p_para = 'arquivado' THEN v_papel IN ('aprovador','admin_sgs')
    ELSE false END;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'Transição % → % não permitida para o papel %', v.estado, p_para, v_papel;
  END IF;

  PERFORM set_config('sgs.transicao', 'on', true);

  IF p_para = 'em_revisao' THEN
    UPDATE public.versoes SET estado = 'em_revisao',
           revisor_id = coalesce(revisor_id, CASE WHEN v_papel <> 'autor' THEN v_uid END)
     WHERE id = v.id;
  ELSIF p_para = 'rascunho' THEN
    UPDATE public.versoes SET estado = 'rascunho' WHERE id = v.id;
  ELSIF p_para = 'aprovado' THEN
    SELECT NOT EXISTS (SELECT 1 FROM public.versoes
                        WHERE documento_id = v.documento_id AND aprovado_em IS NOT NULL AND id <> v.id)
      INTO v_primeira;
    UPDATE public.versoes SET estado = 'aprovado', aprovador_id = v_uid, aprovado_em = now(),
           data_criacao = CASE WHEN v_primeira THEN current_date ELSE data_criacao END
     WHERE id = v.id;
  ELSIF p_para = 'vigente' THEN
    SELECT * INTO v_ant FROM public.versoes
     WHERE documento_id = v.documento_id AND estado = 'vigente' FOR UPDATE;
    IF FOUND THEN
      UPDATE public.versoes SET estado = 'substituido', vigencia_fim = coalesce(p_vigencia, current_date)
       WHERE id = v_ant.id;
      INSERT INTO public.transicoes_versao (versao_id, de, para, usuario_id, comentario)
      VALUES (v_ant.id, 'vigente', 'substituido', v_uid, 'Substituída pela versão ' || v.versao);
    END IF;
    UPDATE public.versoes SET estado = 'vigente',
           vigencia_inicio = coalesce(p_vigencia, current_date),
           proxima_revisao = coalesce(proxima_revisao, (coalesce(p_vigencia, current_date) + interval '12 months')::date)
     WHERE id = v.id;
  ELSIF p_para = 'arquivado' THEN
    UPDATE public.versoes SET estado = 'arquivado',
           vigencia_fim = CASE WHEN v.estado = 'vigente' THEN current_date ELSE vigencia_fim END
     WHERE id = v.id;
  END IF;

  INSERT INTO public.transicoes_versao (versao_id, de, para, usuario_id, comentario)
  VALUES (v.id, v.estado, p_para, v_uid, p_comentario);
  PERFORM set_config('sgs.transicao', 'off', true);
END $$;

CREATE OR REPLACE FUNCTION public.sgs_nova_versao(
  p_base_versao_id bigint,
  p_motivo         text,
  p_mudanca_maior  boolean DEFAULT false
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  b public.versoes%ROWTYPE; v_maior int; v_menor int; v_id bigint; v_papel public.papel_usuario;
BEGIN
  SELECT * INTO b FROM public.versoes WHERE id = p_base_versao_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Versão-base % não encontrada', p_base_versao_id; END IF;
  v_papel := public.sgs_papel(b.empresa_id);
  IF v_papel IS NULL THEN RAISE EXCEPTION 'Versão-base % não encontrada', p_base_versao_id; END IF;
  IF v_papel IN ('equipe_campo', 'leitura') THEN
    RAISE EXCEPTION 'Sem permissão para criar versões';
  END IF;
  SELECT max(maior) INTO v_maior FROM public.versoes WHERE documento_id = b.documento_id;
  IF p_mudanca_maior THEN
    v_maior := v_maior + 1; v_menor := 0;
  ELSE
    SELECT max(menor) + 1 INTO v_menor FROM public.versoes
     WHERE documento_id = b.documento_id AND maior = v_maior;
  END IF;
  INSERT INTO public.versoes (documento_id, empresa_id, maior, menor, base_versao_id, autor_id, motivo, conteudo)
  VALUES (b.documento_id, b.empresa_id, v_maior, v_menor, b.id, auth.uid(), p_motivo, b.conteudo)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- ---------------------------------------------------------------------------
-- Visões (com a empresa)
-- ---------------------------------------------------------------------------
DROP VIEW public.v_revisoes_a_vencer;
DROP VIEW public.v_documentos;
CREATE VIEW public.v_documentos WITH (security_invoker = true) AS
SELECT d.id, d.empresa_id, d.requisito, d.titulo, d.assunto, d.produto_id, p.nome AS produto,
       'Documento ' || d.requisito || ' – ' || d.titulo
         || coalesce(' – ' || d.assunto, '') || coalesce(' – ' || p.nome, '') AS nome,
       vg.id AS versao_vigente_id, vg.versao AS versao_vigente, vg.vigencia_inicio, vg.proxima_revisao,
       va.id AS versao_andamento_id, va.versao AS versao_andamento, va.estado AS estado_andamento
  FROM public.documentos d
  LEFT JOIN public.produtos p ON p.id = d.produto_id
  LEFT JOIN public.versoes vg ON vg.documento_id = d.id AND vg.estado = 'vigente'
  LEFT JOIN public.versoes va ON va.documento_id = d.id AND va.estado IN ('rascunho','em_revisao','aprovado');
CREATE VIEW public.v_revisoes_a_vencer WITH (security_invoker = true) AS
SELECT id, empresa_id, nome, versao_vigente, proxima_revisao, (proxima_revisao - current_date) AS dias_restantes
  FROM public.v_documentos
 WHERE proxima_revisao <= current_date + 30;

-- ---------------------------------------------------------------------------
-- Segurança por linha (RLS): sempre dentro da empresa
-- ---------------------------------------------------------------------------
ALTER TABLE public.empresas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.membros  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.convites ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['perfis','produtos','itens_mapa','progresso_itens','documentos','versoes',
                           'transicoes_versao','decisoes','auditoria','assinaturas'] LOOP
    EXECUTE (SELECT string_agg(format('DROP POLICY %I ON public.%I;', policyname, t), ' ')
               FROM pg_policies WHERE schemaname = 'public' AND tablename = t);
  END LOOP;
END $$;

-- Empresas: o membro ativo vê a sua (mesmo aguardando, para mostrar a situação). O Responsável edita os dados.
CREATE POLICY ler ON public.empresas FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.membros m WHERE m.empresa_id = empresas.id AND m.perfil_id = auth.uid() AND m.ativo));
CREATE POLICY editar ON public.empresas FOR UPDATE TO authenticated
  USING (public.sgs_papel(id) = 'admin_sgs') WITH CHECK (public.sgs_papel(id) = 'admin_sgs');

-- Membros: cada um vê os próprios vínculos; o Responsável vê e administra os da empresa.
CREATE POLICY ler ON public.membros FOR SELECT TO authenticated
  USING (perfil_id = auth.uid() OR public.sgs_papel(empresa_id) = 'admin_sgs');
CREATE POLICY editar ON public.membros FOR UPDATE TO authenticated
  USING (public.sgs_papel(empresa_id) = 'admin_sgs') WITH CHECK (public.sgs_papel(empresa_id) = 'admin_sgs');

-- Convites: o Responsável vê e cancela (criação só por sgs_convidar).
CREATE POLICY ler ON public.convites FOR SELECT TO authenticated
  USING (public.sgs_papel(empresa_id) = 'admin_sgs');
CREATE POLICY cancelar ON public.convites FOR DELETE TO authenticated
  USING (public.sgs_papel(empresa_id) = 'admin_sgs' AND aceito_em IS NULL);

-- Perfis: o próprio; e o Responsável vê as pessoas da sua empresa.
CREATE POLICY ler ON public.perfis FOR SELECT TO authenticated
  USING (id = auth.uid() OR EXISTS (SELECT 1 FROM public.membros m
                                     WHERE m.perfil_id = perfis.id AND public.sgs_papel(m.empresa_id) = 'admin_sgs'));
CREATE POLICY editar ON public.perfis FOR UPDATE TO authenticated
  USING (id = auth.uid()) WITH CHECK (id = auth.uid());

-- Catálogo do mapa: igual para todos que estão em alguma empresa ativa.
CREATE POLICY ler ON public.itens_mapa FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.membros m JOIN public.empresas e ON e.id = m.empresa_id
                  WHERE m.perfil_id = auth.uid() AND m.ativo AND e.situacao = 'ativa'));

-- Dados do SGS: membro ativo da empresa lê; quem edita escreve.
CREATE POLICY ler ON public.produtos          FOR SELECT TO authenticated USING (public.sgs_papel(empresa_id) IS NOT NULL);
CREATE POLICY ler ON public.progresso_itens   FOR SELECT TO authenticated USING (public.sgs_papel(empresa_id) IS NOT NULL);
CREATE POLICY ler ON public.documentos        FOR SELECT TO authenticated USING (public.sgs_papel(empresa_id) IS NOT NULL);
CREATE POLICY ler ON public.transicoes_versao FOR SELECT TO authenticated USING (public.sgs_papel(empresa_id) IS NOT NULL);
CREATE POLICY ler ON public.decisoes          FOR SELECT TO authenticated USING (public.sgs_papel(empresa_id) IS NOT NULL);
-- Equipe de campo só vê versões vigentes.
CREATE POLICY ler ON public.versoes FOR SELECT TO authenticated
  USING (public.sgs_papel(empresa_id) IS NOT NULL
         AND (public.sgs_papel(empresa_id) <> 'equipe_campo' OR estado = 'vigente'));
CREATE POLICY ler ON public.auditoria FOR SELECT TO authenticated
  USING (public.sgs_papel(empresa_id) IN ('admin_sgs', 'aprovador'));

CREATE POLICY incluir ON public.produtos FOR INSERT TO authenticated WITH CHECK (public.sgs_pode_editar(empresa_id));
CREATE POLICY editar  ON public.produtos FOR UPDATE TO authenticated
  USING (public.sgs_pode_editar(empresa_id)) WITH CHECK (public.sgs_pode_editar(empresa_id));
CREATE POLICY incluir ON public.progresso_itens FOR INSERT TO authenticated WITH CHECK (public.sgs_pode_editar(empresa_id));
CREATE POLICY editar  ON public.progresso_itens FOR UPDATE TO authenticated
  USING (public.sgs_pode_editar(empresa_id)) WITH CHECK (public.sgs_pode_editar(empresa_id));
CREATE POLICY incluir ON public.documentos FOR INSERT TO authenticated
  WITH CHECK (public.sgs_pode_editar(empresa_id) OR public.sgs_papel(empresa_id) = 'agente_ia');
CREATE POLICY incluir ON public.versoes FOR INSERT TO authenticated
  WITH CHECK ((public.sgs_pode_editar(empresa_id) OR public.sgs_papel(empresa_id) = 'agente_ia') AND autor_id = auth.uid());
CREATE POLICY editar ON public.versoes FOR UPDATE TO authenticated
  USING (estado = 'rascunho' AND (public.sgs_pode_editar(empresa_id)
         OR (public.sgs_papel(empresa_id) = 'agente_ia' AND autor_id = auth.uid())));
CREATE POLICY incluir ON public.decisoes FOR INSERT TO authenticated
  WITH CHECK (public.sgs_papel(empresa_id) IN ('admin_sgs', 'aprovador'));

-- Assinaturas: cada um grava a sua; vê as de quem está numa empresa ativa em comum.
CREATE FUNCTION public.sgs_mesma_empresa(p_perfil uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.membros dono JOIN public.membros eu ON eu.empresa_id = dono.empresa_id
                  WHERE dono.perfil_id = p_perfil AND eu.perfil_id = auth.uid() AND eu.ativo
                    AND public.sgs_papel(eu.empresa_id) IS NOT NULL)
$$;
REVOKE EXECUTE ON FUNCTION public.sgs_mesma_empresa(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sgs_mesma_empresa(uuid) TO authenticated;
CREATE POLICY ler ON public.assinaturas FOR SELECT TO authenticated
  USING (perfil_id = auth.uid() OR public.sgs_mesma_empresa(perfil_id));
CREATE POLICY incluir ON public.assinaturas FOR INSERT TO authenticated
  WITH CHECK (perfil_id = auth.uid());
CREATE POLICY editar ON public.assinaturas FOR UPDATE TO authenticated
  USING (perfil_id = auth.uid()) WITH CHECK (perfil_id = auth.uid());

-- Permissões das tabelas e funções novas.
REVOKE ALL ON public.empresas, public.membros, public.convites FROM anon, authenticated;
GRANT SELECT, UPDATE (nome, cnpj, municipio, uf, logo_path) ON public.empresas TO authenticated;
GRANT SELECT, UPDATE (papel, ativo) ON public.membros TO authenticated;
GRANT SELECT, DELETE ON public.convites TO authenticated;
REVOKE ALL ON public.v_documentos, public.v_revisoes_a_vencer FROM anon;
GRANT SELECT ON public.v_documentos, public.v_revisoes_a_vencer TO authenticated;

REVOKE EXECUTE ON FUNCTION public.fn_empresa_do_pai(), public.fn_protege_empresa(), public.fn_protege_membro(),
  public.fn_aceitar_convites(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sgs_papel(uuid), public.sgs_pode_editar(uuid), public.sgs_admin_plataforma(),
  public.sgs_empresa_padrao(), public.sgs_criar_empresa(text, text, text, text, text), public.sgs_admin_empresas(),
  public.sgs_definir_situacao_empresa(uuid, public.situacao_empresa), public.sgs_convidar(uuid, text, public.papel_usuario),
  public.sgs_aceitar_convites(), public.sgs_marcar_item(uuid, text, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sgs_papel(uuid), public.sgs_pode_editar(uuid), public.sgs_admin_plataforma(),
  public.sgs_empresa_padrao(), public.sgs_criar_empresa(text, text, text, text, text), public.sgs_admin_empresas(),
  public.sgs_definir_situacao_empresa(uuid, public.situacao_empresa), public.sgs_convidar(uuid, text, public.papel_usuario),
  public.sgs_aceitar_convites(), public.sgs_marcar_item(uuid, text, text, boolean) TO authenticated;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- ---------------------------------------------------------------------------
-- Arquivos (Storage): cada empresa na sua pasta  documentos/<empresa_id>/...
-- ---------------------------------------------------------------------------
DROP POLICY sgs_arquivos_ler ON storage.objects;
DROP POLICY sgs_arquivos_incluir ON storage.objects;
CREATE FUNCTION public.sgs_empresa_do_caminho(p_nome text) RETURNS uuid
LANGUAGE plpgsql IMMUTABLE SET search_path = public AS $$
BEGIN
  RETURN split_part(p_nome, '/', 1)::uuid;
EXCEPTION WHEN others THEN RETURN NULL;
END $$;
GRANT EXECUTE ON FUNCTION public.sgs_empresa_do_caminho(text) TO authenticated;
CREATE POLICY sgs_arquivos_ler ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'documentos' AND public.sgs_papel(public.sgs_empresa_do_caminho(name)) IS NOT NULL);
CREATE POLICY sgs_arquivos_incluir ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'documentos'
              AND (public.sgs_pode_editar(public.sgs_empresa_do_caminho(name))
                   OR public.sgs_papel(public.sgs_empresa_do_caminho(name)) = 'agente_ia'));

COMMIT;
