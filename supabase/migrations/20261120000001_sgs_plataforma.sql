-- SGS Turismo – Trilhas do Sul · banco da plataforma (Supabase / PostgreSQL 15+)
--
-- Regras de negócio (decisões de Vagner):
--  * Documento sem código: o nome é o requisito que atende
--    ("Documento 4.1 – Contexto da Organização", "Documento 8.2 – PAE – Poço de Ferro").
--  * A primeira versão é 1.0 e fica 1.0 durante o rascunho; a data de criação
--    só é preenchida quando a 1.0 é aprovada.
--  * Fluxo: Rascunho → Em revisão → Aprovado → Vigente → Substituído ou Arquivado.
--    Uma única versão vigente por documento; troca de vigência na mesma transação.
--  * Documentos da empresa são únicos; documentos de operação são de cada produto (20/11/2026).
--  * O papel agente_ia só cria rascunhos.
--  * Histórico (transições, decisões, auditoria) é somente inclusão.

BEGIN;

-- ---------------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------------
CREATE TYPE public.papel_usuario AS ENUM (
  'admin_sgs', 'aprovador', 'revisor', 'autor', 'equipe_campo', 'leitura', 'agente_ia'
);
CREATE TYPE public.estado_versao AS ENUM (
  'rascunho', 'em_revisao', 'aprovado', 'vigente', 'substituido', 'arquivado'
);
CREATE TYPE public.escopo_item AS ENUM ('empresa', 'produto');
CREATE TYPE public.origem_obrigacao AS ENUM ('norma', 'requisito_legal', 'regra_interna', 'recomendacao');

-- ---------------------------------------------------------------------------
-- Pessoas
-- ---------------------------------------------------------------------------
CREATE TABLE public.perfis (
  id        uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT,
  nome      text NOT NULL DEFAULT '',
  email     text,
  papel     public.papel_usuario NOT NULL DEFAULT 'leitura',
  ativo     boolean NOT NULL DEFAULT false,
  criado_em timestamptz NOT NULL DEFAULT now()
);

-- Papel do usuário logado (NULL se não tiver perfil ativo).
CREATE FUNCTION public.sgs_papel() RETURNS public.papel_usuario
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT papel FROM public.perfis WHERE id = auth.uid() AND ativo
$$;

CREATE FUNCTION public.sgs_pode_editar() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(public.sgs_papel() IN ('admin_sgs', 'aprovador', 'revisor', 'autor'), false)
$$;

-- Novo login ganha perfil inativo. O primeiro usuário do sistema vira responsável pelo SGS.
CREATE FUNCTION public.fn_novo_usuario() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_primeiro boolean;
BEGIN
  PERFORM pg_advisory_xact_lock(21101);
  SELECT NOT EXISTS (SELECT 1 FROM public.perfis) INTO v_primeiro;
  INSERT INTO public.perfis (id, nome, email, papel, ativo)
  VALUES (NEW.id, coalesce(NEW.raw_user_meta_data->>'name', NEW.raw_user_meta_data->>'full_name', ''),
          NEW.email,
          CASE WHEN v_primeiro THEN 'admin_sgs'::public.papel_usuario ELSE 'leitura' END,
          v_primeiro);
  RETURN NEW;
END $$;

CREATE TRIGGER trg_novo_usuario AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.fn_novo_usuario();

-- Só o responsável pelo SGS muda papel e ativação; cada um pode mudar o próprio nome.
CREATE FUNCTION public.fn_protege_perfil() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF (NEW.papel, NEW.ativo, NEW.id) IS DISTINCT FROM (OLD.papel, OLD.ativo, OLD.id)
     AND coalesce(public.sgs_papel() <> 'admin_sgs', true)
     AND auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Só o responsável pelo SGS muda papel ou ativação de usuários';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_protege_perfil BEFORE UPDATE ON public.perfis
  FOR EACH ROW EXECUTE FUNCTION public.fn_protege_perfil();

-- ---------------------------------------------------------------------------
-- Produtos (roteiros) e itens do mapa
-- ---------------------------------------------------------------------------
CREATE TABLE public.produtos (
  id            text PRIMARY KEY CHECK (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  nome          text NOT NULL CHECK (length(trim(nome)) > 0),
  municipio     text NOT NULL DEFAULT '',
  base          text NOT NULL DEFAULT '',
  atividades    text[] NOT NULL DEFAULT '{}',
  responsavel   text NOT NULL DEFAULT '',
  situacao      text NOT NULL DEFAULT 'Em implantação'
                CHECK (situacao IN ('Em implantação', 'Implantado', 'Em revisão')),
  descricao     text NOT NULL DEFAULT '',
  piloto        boolean NOT NULL DEFAULT false,
  exemplo       boolean NOT NULL DEFAULT false,   -- dado fictício de demonstração
  ordem         int NOT NULL DEFAULT 100,
  arquivado     boolean NOT NULL DEFAULT false,   -- "Excluir" na tela arquiva: o histórico fica
  criado_por    uuid REFERENCES public.perfis(id) DEFAULT auth.uid(),
  criado_em     timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX produtos_nome_unico ON public.produtos (lower(nome)) WHERE NOT arquivado;

CREATE TABLE public.itens_mapa (
  item          text PRIMARY KEY,
  tipo          text NOT NULL CHECK (tipo IN ('documento', 'registro')),
  requisito     text NOT NULL,
  titulo        text NOT NULL,
  escopo        public.escopo_item NOT NULL,
  exigido_norma boolean NOT NULL,
  ordem         int NOT NULL
);

-- "Já tenho este item": empresa (produto_id NULL) ou produto.
CREATE TABLE public.progresso_itens (
  id             bigserial PRIMARY KEY,
  item           text NOT NULL REFERENCES public.itens_mapa(item),
  produto_id     text REFERENCES public.produtos(id),
  pronto         boolean NOT NULL DEFAULT true,
  atualizado_por uuid REFERENCES public.perfis(id) DEFAULT auth.uid(),
  atualizado_em  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX progresso_unico ON public.progresso_itens (item, coalesce(produto_id, ''));

CREATE FUNCTION public.fn_valida_escopo() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
DECLARE v_escopo public.escopo_item;
BEGIN
  IF NEW.item IS NULL THEN RETURN NEW; END IF;
  SELECT escopo INTO v_escopo FROM public.itens_mapa WHERE item = NEW.item;
  IF v_escopo = 'empresa' AND NEW.produto_id IS NOT NULL THEN
    RAISE EXCEPTION 'O item % é da empresa e vale para todos os produtos', NEW.item;
  END IF;
  IF v_escopo = 'produto' AND NEW.produto_id IS NULL THEN
    RAISE EXCEPTION 'O item % é de operação e precisa de um produto', NEW.item;
  END IF;
  IF TG_TABLE_NAME = 'progresso_itens' THEN
    NEW.atualizado_em := now();
    NEW.atualizado_por := coalesce(auth.uid(), NEW.atualizado_por);
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_valida_escopo BEFORE INSERT OR UPDATE ON public.progresso_itens
  FOR EACH ROW EXECUTE FUNCTION public.fn_valida_escopo();

CREATE FUNCTION public.fn_toca_atualizado() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.atualizado_em := now(); RETURN NEW; END $$;
CREATE TRIGGER trg_toca BEFORE UPDATE ON public.produtos
  FOR EACH ROW EXECUTE FUNCTION public.fn_toca_atualizado();

-- ---------------------------------------------------------------------------
-- Documentos (cadastro estável) e versões
-- ---------------------------------------------------------------------------
CREATE TABLE public.documentos (
  id          bigserial PRIMARY KEY,
  requisito   text NOT NULL CHECK (requisito ~ '^(4|5|6|7|8|9|10)(\.[0-9]+)*$'),
  titulo      text NOT NULL CHECK (length(trim(titulo)) > 0),     -- ex.: "Contexto da Organização"
  assunto     text,                                               -- quando há mais de um no mesmo requisito
  produto_id  text REFERENCES public.produtos(id),                -- NULL = documento da empresa
  item        text REFERENCES public.itens_mapa(item),            -- nó do mapa a que pertence
  origem      public.origem_obrigacao NOT NULL DEFAULT 'norma',
  criado_por  uuid REFERENCES public.perfis(id) DEFAULT auth.uid(),
  criado_em   timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX documentos_unicos
  ON public.documentos (requisito, coalesce(produto_id, ''), lower(coalesce(assunto, '')));

CREATE TRIGGER trg_valida_escopo BEFORE INSERT OR UPDATE ON public.documentos
  FOR EACH ROW EXECUTE FUNCTION public.fn_valida_escopo();

CREATE TABLE public.versoes (
  id              bigserial PRIMARY KEY,
  documento_id    bigint NOT NULL REFERENCES public.documentos(id),
  maior           int NOT NULL DEFAULT 1 CHECK (maior >= 1),
  menor           int NOT NULL DEFAULT 0 CHECK (menor >= 0),
  versao          text GENERATED ALWAYS AS (maior || '.' || menor) STORED,
  estado          public.estado_versao NOT NULL DEFAULT 'rascunho',
  base_versao_id  bigint REFERENCES public.versoes(id),
  conteudo        jsonb NOT NULL DEFAULT '{}'::jsonb,   -- o que foi preenchido no mapa
  motivo          text NOT NULL DEFAULT 'Primeira versão',
  resumo_mudancas text,
  autor_id        uuid NOT NULL REFERENCES public.perfis(id) DEFAULT auth.uid(),
  revisor_id      uuid REFERENCES public.perfis(id),
  aprovador_id    uuid REFERENCES public.perfis(id),
  aprovado_em     timestamptz,
  data_criacao    date,          -- preenchida na aprovação da primeira versão
  vigencia_inicio date,
  vigencia_fim    date,
  proxima_revisao date,
  arquivo_path    text,          -- arquivo no Storage (bucket "documentos")
  criado_em       timestamptz NOT NULL DEFAULT now(),
  atualizado_em   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (documento_id, maior, menor),
  CONSTRAINT aprovada_tem_aprovador CHECK (
    estado IN ('rascunho', 'em_revisao') OR (aprovador_id IS NOT NULL AND aprovado_em IS NOT NULL)),
  CONSTRAINT vigente_tem_datas CHECK (
    estado <> 'vigente' OR (vigencia_inicio IS NOT NULL AND proxima_revisao IS NOT NULL))
);
CREATE UNIQUE INDEX uma_vigente_por_documento ON public.versoes (documento_id) WHERE estado = 'vigente';
-- Só uma versão em andamento (rascunho, em revisão ou aprovada) por documento.
CREATE UNIQUE INDEX uma_em_andamento_por_documento ON public.versoes (documento_id)
  WHERE estado IN ('rascunho', 'em_revisao', 'aprovado');

CREATE TABLE public.transicoes_versao (
  id         bigserial PRIMARY KEY,
  versao_id  bigint NOT NULL REFERENCES public.versoes(id),
  de         public.estado_versao,
  para       public.estado_versao NOT NULL,
  usuario_id uuid REFERENCES public.perfis(id),
  comentario text,
  em         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.decisoes (
  id            bigserial PRIMARY KEY,
  descricao     text NOT NULL,
  decidido_por  text NOT NULL,          -- quem decidiu (pessoa autorizada pelo SGS)
  decidido_em   timestamptz NOT NULL,
  produto_id    text REFERENCES public.produtos(id),
  referencia    text,
  registrado_por uuid REFERENCES public.perfis(id) DEFAULT auth.uid(),
  registrado_em timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.auditoria (
  id           bigserial PRIMARY KEY,
  tabela       text NOT NULL,
  registro_id  text,
  operacao     text NOT NULL,
  dados_antes  jsonb,
  dados_depois jsonb,
  usuario_id   uuid,
  em           timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Gatilhos de proteção e auditoria
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.fn_auditoria() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_antes  jsonb := CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END;
  v_depois jsonb := CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END;
BEGIN
  INSERT INTO public.auditoria (tabela, registro_id, operacao, dados_antes, dados_depois, usuario_id)
  VALUES (TG_TABLE_NAME, coalesce(v_depois, v_antes)->>'id', TG_OP, v_antes, v_depois, auth.uid());
  RETURN NULL;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['perfis','produtos','progresso_itens','documentos','versoes','decisoes'] LOOP
    EXECUTE format('CREATE TRIGGER trg_auditoria AFTER INSERT OR UPDATE OR DELETE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.fn_auditoria()', t);
  END LOOP;
END $$;

CREATE FUNCTION public.fn_somente_inclusao() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'A tabela % só aceita inclusão: o histórico não pode ser alterado nem apagado', TG_TABLE_NAME;
END $$;
CREATE TRIGGER trg_somente_inclusao BEFORE UPDATE OR DELETE ON public.transicoes_versao
  FOR EACH ROW EXECUTE FUNCTION public.fn_somente_inclusao();
CREATE TRIGGER trg_somente_inclusao BEFORE UPDATE OR DELETE ON public.auditoria
  FOR EACH ROW EXECUTE FUNCTION public.fn_somente_inclusao();
CREATE TRIGGER trg_somente_inclusao BEFORE UPDATE OR DELETE ON public.decisoes
  FOR EACH ROW EXECUTE FUNCTION public.fn_somente_inclusao();
-- Produtos e documentos não são apagados (produto é arquivado).
CREATE TRIGGER trg_sem_exclusao BEFORE DELETE ON public.produtos
  FOR EACH ROW EXECUTE FUNCTION public.fn_somente_inclusao();
CREATE TRIGGER trg_sem_exclusao BEFORE DELETE ON public.documentos
  FOR EACH ROW EXECUTE FUNCTION public.fn_somente_inclusao();

CREATE FUNCTION public.fn_protege_versao() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Versões não podem ser apagadas; use o estado Arquivado';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.estado <> 'rascunho' OR NEW.aprovador_id IS NOT NULL OR NEW.aprovado_em IS NOT NULL
       OR NEW.data_criacao IS NOT NULL OR NEW.vigencia_inicio IS NOT NULL OR NEW.vigencia_fim IS NOT NULL THEN
      RAISE EXCEPTION 'Toda versão nasce como Rascunho, sem aprovação, data de criação nem vigência';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.documento_id <> OLD.documento_id OR NEW.autor_id <> OLD.autor_id THEN
    RAISE EXCEPTION 'Uma versão não pode mudar de documento nem de autor';
  END IF;
  NEW.atualizado_em := now();
  IF coalesce(current_setting('sgs.transicao', true), '') = 'on' THEN
    RETURN NEW;
  END IF;
  IF NEW.estado IS DISTINCT FROM OLD.estado THEN
    RAISE EXCEPTION 'O estado de uma versão só muda pela função sgs_transicionar()';
  END IF;
  IF OLD.estado <> 'rascunho' THEN
    RAISE EXCEPTION 'Versão em estado % não pode ser alterada; crie uma nova versão', OLD.estado;
  END IF;
  IF (NEW.aprovador_id, NEW.aprovado_em, NEW.data_criacao, NEW.vigencia_inicio, NEW.vigencia_fim, NEW.maior, NEW.menor)
     IS DISTINCT FROM
     (OLD.aprovador_id, OLD.aprovado_em, OLD.data_criacao, OLD.vigencia_inicio, OLD.vigencia_fim, OLD.maior, OLD.menor) THEN
    RAISE EXCEPTION 'Aprovação, datas e numeração só mudam pela função sgs_transicionar()';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_protege_versao BEFORE INSERT OR UPDATE OR DELETE ON public.versoes
  FOR EACH ROW EXECUTE FUNCTION public.fn_protege_versao();

CREATE FUNCTION public.fn_versao_criada() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.transicoes_versao (versao_id, de, para, usuario_id, comentario)
  VALUES (NEW.id, NULL, 'rascunho', NEW.autor_id, 'Versão criada');
  RETURN NULL;
END $$;
CREATE TRIGGER trg_versao_criada AFTER INSERT ON public.versoes
  FOR EACH ROW EXECUTE FUNCTION public.fn_versao_criada();

-- ---------------------------------------------------------------------------
-- Fluxo de aprovação (única porta para mudar o estado)
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.sgs_transicionar(
  p_versao_id  bigint,
  p_para       public.estado_versao,
  p_comentario text DEFAULT NULL,
  p_vigencia   date DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v       public.versoes%ROWTYPE;
  v_ant   public.versoes%ROWTYPE;
  v_papel public.papel_usuario := public.sgs_papel();
  v_uid   uuid := auth.uid();
  v_ok    boolean;
  v_primeira boolean;
BEGIN
  SELECT * INTO v FROM public.versoes WHERE id = p_versao_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Versão % não encontrada', p_versao_id; END IF;
  IF v_papel IS NULL THEN RAISE EXCEPTION 'Usuário sem perfil ativo'; END IF;
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

-- Nova versão a partir de outra (revisão ou recuperação). Sempre nasce como Rascunho.
CREATE FUNCTION public.sgs_nova_versao(
  p_base_versao_id bigint,
  p_motivo         text,
  p_mudanca_maior  boolean DEFAULT false
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  b public.versoes%ROWTYPE; v_maior int; v_menor int; v_id bigint;
BEGIN
  IF public.sgs_papel() IS NULL OR public.sgs_papel() IN ('equipe_campo', 'leitura') THEN
    RAISE EXCEPTION 'Sem permissão para criar versões';
  END IF;
  SELECT * INTO b FROM public.versoes WHERE id = p_base_versao_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Versão-base % não encontrada', p_base_versao_id; END IF;
  SELECT max(maior) INTO v_maior FROM public.versoes WHERE documento_id = b.documento_id;
  IF p_mudanca_maior THEN
    v_maior := v_maior + 1; v_menor := 0;
  ELSE
    SELECT max(menor) + 1 INTO v_menor FROM public.versoes
     WHERE documento_id = b.documento_id AND maior = v_maior;
  END IF;
  INSERT INTO public.versoes (documento_id, maior, menor, base_versao_id, autor_id, motivo, conteudo)
  VALUES (b.documento_id, v_maior, v_menor, b.id, auth.uid(), p_motivo, b.conteudo)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- Marca ou desmarca "Já tenho este item" (empresa: p_produto NULL). Respeita a RLS de quem chama.
CREATE FUNCTION public.sgs_marcar_item(p_item text, p_produto text, p_pronto boolean) RETURNS void
LANGUAGE sql SECURITY INVOKER SET search_path = public AS $$
  INSERT INTO public.progresso_itens (item, produto_id, pronto) VALUES (p_item, p_produto, p_pronto)
  ON CONFLICT (item, (coalesce(produto_id, ''))) DO UPDATE SET pronto = EXCLUDED.pronto
$$;

-- ---------------------------------------------------------------------------
-- Visões
-- ---------------------------------------------------------------------------
CREATE VIEW public.v_documentos WITH (security_invoker = true) AS
SELECT d.id, d.requisito, d.titulo, d.assunto, d.produto_id, p.nome AS produto,
       'Documento ' || d.requisito || ' – ' || d.titulo
         || coalesce(' – ' || d.assunto, '') || coalesce(' – ' || p.nome, '') AS nome,
       vg.id AS versao_vigente_id, vg.versao AS versao_vigente, vg.vigencia_inicio, vg.proxima_revisao,
       va.id AS versao_andamento_id, va.versao AS versao_andamento, va.estado AS estado_andamento
  FROM public.documentos d
  LEFT JOIN public.produtos p ON p.id = d.produto_id
  LEFT JOIN public.versoes vg ON vg.documento_id = d.id AND vg.estado = 'vigente'
  LEFT JOIN public.versoes va ON va.documento_id = d.id AND va.estado IN ('rascunho','em_revisao','aprovado');

CREATE VIEW public.v_revisoes_a_vencer WITH (security_invoker = true) AS
SELECT id, nome, versao_vigente, proxima_revisao, (proxima_revisao - current_date) AS dias_restantes
  FROM public.v_documentos
 WHERE proxima_revisao <= current_date + 30;

-- ---------------------------------------------------------------------------
-- Segurança por linha (RLS)
-- ---------------------------------------------------------------------------
ALTER TABLE public.perfis            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.produtos          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.itens_mapa        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.progresso_itens   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documentos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.versoes           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transicoes_versao ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.decisoes          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auditoria         ENABLE ROW LEVEL SECURITY;

-- Perfis: cada um vê o seu; o responsável vê e administra todos.
CREATE POLICY perfis_ler ON public.perfis FOR SELECT TO authenticated
  USING (id = auth.uid() OR public.sgs_papel() = 'admin_sgs');
CREATE POLICY perfis_editar ON public.perfis FOR UPDATE TO authenticated
  USING (id = auth.uid() OR public.sgs_papel() = 'admin_sgs');

-- Leitura: qualquer perfil ativo.
CREATE POLICY ler ON public.produtos          FOR SELECT TO authenticated USING (public.sgs_papel() IS NOT NULL);
CREATE POLICY ler ON public.itens_mapa        FOR SELECT TO authenticated USING (public.sgs_papel() IS NOT NULL);
CREATE POLICY ler ON public.progresso_itens   FOR SELECT TO authenticated USING (public.sgs_papel() IS NOT NULL);
CREATE POLICY ler ON public.documentos        FOR SELECT TO authenticated USING (public.sgs_papel() IS NOT NULL);
CREATE POLICY ler ON public.transicoes_versao FOR SELECT TO authenticated USING (public.sgs_papel() IS NOT NULL);
CREATE POLICY ler ON public.decisoes          FOR SELECT TO authenticated USING (public.sgs_papel() IS NOT NULL);
-- Equipe de campo só vê versões vigentes.
CREATE POLICY ler ON public.versoes FOR SELECT TO authenticated
  USING (public.sgs_papel() IS NOT NULL AND (public.sgs_papel() <> 'equipe_campo' OR estado = 'vigente'));
CREATE POLICY ler ON public.auditoria FOR SELECT TO authenticated
  USING (public.sgs_papel() IN ('admin_sgs', 'aprovador'));

-- Escrita.
CREATE POLICY incluir ON public.produtos FOR INSERT TO authenticated WITH CHECK (public.sgs_pode_editar());
CREATE POLICY editar  ON public.produtos FOR UPDATE TO authenticated USING (public.sgs_pode_editar());
CREATE POLICY incluir ON public.progresso_itens FOR INSERT TO authenticated WITH CHECK (public.sgs_pode_editar());
CREATE POLICY editar  ON public.progresso_itens FOR UPDATE TO authenticated USING (public.sgs_pode_editar());
CREATE POLICY incluir ON public.documentos FOR INSERT TO authenticated
  WITH CHECK (public.sgs_pode_editar() OR public.sgs_papel() = 'agente_ia');
CREATE POLICY incluir ON public.versoes FOR INSERT TO authenticated
  WITH CHECK ((public.sgs_pode_editar() OR public.sgs_papel() = 'agente_ia') AND autor_id = auth.uid());
CREATE POLICY editar ON public.versoes FOR UPDATE TO authenticated
  USING (estado = 'rascunho' AND (public.sgs_pode_editar() OR (public.sgs_papel() = 'agente_ia' AND autor_id = auth.uid())));
CREATE POLICY incluir ON public.decisoes FOR INSERT TO authenticated
  WITH CHECK (public.sgs_papel() IN ('admin_sgs', 'aprovador'));

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT INSERT, UPDATE ON public.produtos, public.progresso_itens, public.documentos, public.versoes, public.perfis TO authenticated;
GRANT INSERT ON public.decisoes TO authenticated;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
GRANT EXECUTE ON FUNCTION public.sgs_transicionar(bigint, public.estado_versao, text, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sgs_nova_versao(bigint, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sgs_marcar_item(text, text, boolean) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.sgs_marcar_item(text, text, boolean) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.sgs_transicionar(bigint, public.estado_versao, text, date) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.sgs_nova_versao(bigint, text, boolean) FROM anon, public;

-- ---------------------------------------------------------------------------
-- Arquivos (Storage): bucket privado, acesso validado no servidor
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public) VALUES ('documentos', 'documentos', false)
  ON CONFLICT (id) DO NOTHING;
CREATE POLICY sgs_arquivos_ler ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'documentos' AND public.sgs_papel() IS NOT NULL);
CREATE POLICY sgs_arquivos_incluir ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'documentos' AND (public.sgs_pode_editar() OR public.sgs_papel() = 'agente_ia'));

COMMIT;
