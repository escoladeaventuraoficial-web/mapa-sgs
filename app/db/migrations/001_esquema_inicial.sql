-- SGS Trilhas do Sul – esquema inicial (PostgreSQL 14+)
-- Implementa o padrão TS-PG-GER-001: código estável por documento, registro por versão,
-- fluxo Rascunho → Em revisão → Aprovado → Vigente → Substituído/Arquivado,
-- uma única versão vigente por código, histórico preservado e trilha de auditoria.

BEGIN;

CREATE TABLE IF NOT EXISTS schema_migrations (
  versao      text PRIMARY KEY,
  aplicada_em timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Tipos enumerados
-- ---------------------------------------------------------------------------
CREATE TYPE papel_usuario AS ENUM (
  'admin_sgs',     -- responsável pelo SGS
  'aprovador',
  'revisor',
  'autor',
  'equipe_campo',  -- consulta a versão vigente dos documentos de campo
  'leitura',
  'agente_ia'      -- só cria rascunhos e propostas
);

CREATE TYPE estado_versao AS ENUM (
  'rascunho', 'em_revisao', 'aprovado', 'vigente', 'substituido', 'arquivado'
);

CREATE TYPE origem_obrigacao AS ENUM (
  'norma', 'requisito_legal', 'regra_interna', 'recomendacao'
);

CREATE TYPE classificacao_acesso AS ENUM ('interno', 'equipe_campo');

CREATE TYPE situacao_requisito AS ENUM (
  'pendente_verificacao', 'elaborado', 'aprovado', 'implementacao_comprovada'
);

CREATE TYPE origem_acao AS ENUM (
  'incidente', 'quase_acidente', 'simulado', 'auditoria', 'analise_critica',
  'revisao_documento', 'inspecao', 'outro'
);

CREATE TYPE estado_acao AS ENUM (
  'aberta', 'em_andamento', 'concluida', 'eficacia_verificada', 'cancelada'
);

CREATE TYPE prioridade AS ENUM ('baixa', 'media', 'alta', 'critica');

-- ---------------------------------------------------------------------------
-- Pessoas e escopo
-- ---------------------------------------------------------------------------
CREATE TABLE usuarios (
  id        bigserial PRIMARY KEY,
  nome      text NOT NULL,
  email     text NOT NULL UNIQUE,
  papel     papel_usuario NOT NULL,
  ativo     boolean NOT NULL DEFAULT true,
  criado_em timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE roteiros (
  sigla     char(3) PRIMARY KEY CHECK (sigla ~ '^[A-Z]{3}$' AND sigla <> 'GER'),
  nome      text NOT NULL,
  descricao text,
  ativo     boolean NOT NULL DEFAULT true,
  criado_em timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE tipos_documento (
  sigla        text PRIMARY KEY CHECK (sigla ~ '^[A-Z]{2,3}$'),
  nome         text NOT NULL,
  descricao    text NOT NULL,
  escopo_usual text NOT NULL
);

-- ---------------------------------------------------------------------------
-- Documentos (cadastro estável) e versões
-- ---------------------------------------------------------------------------
CREATE TABLE documentos (
  id                 bigserial PRIMARY KEY,
  codigo             text NOT NULL UNIQUE,
  titulo             text NOT NULL,
  tipo               text NOT NULL REFERENCES tipos_documento(sigla),
  roteiro_sigla      char(3) REFERENCES roteiros(sigla),   -- NULL = GER
  vinculo_normativo  text NOT NULL,
  origem             origem_obrigacao NOT NULL,
  responsavel_funcao text NOT NULL,
  classificacao      classificacao_acesso NOT NULL DEFAULT 'interno',
  criado_por         bigint NOT NULL REFERENCES usuarios(id),
  criado_em          timestamptz NOT NULL DEFAULT now(),
  -- Registros (REG) não são documentos versionados: ficam na tabela registros.
  CONSTRAINT documento_nao_e_registro CHECK (tipo <> 'REG'),
  -- O código segue TS-TIPO-ESCOPO-NNN e é coerente com tipo e roteiro.
  CONSTRAINT codigo_formato CHECK (
    codigo ~ '^TS-[A-Z]{2,3}-[A-Z]{3}-[0-9]{3}$'
    AND codigo LIKE 'TS-' || tipo || '-' || coalesce(roteiro_sigla, 'GER') || '-___'
  )
);

CREATE TABLE versoes (
  id               bigserial PRIMARY KEY,
  documento_id     bigint NOT NULL REFERENCES documentos(id),
  maior            int NOT NULL CHECK (maior >= 0),
  menor            int NOT NULL CHECK (menor >= 0),
  versao           text GENERATED ALWAYS AS ('v' || maior || '.' || menor) STORED,
  estado           estado_versao NOT NULL DEFAULT 'rascunho',
  base_versao_id   bigint REFERENCES versoes(id),       -- versão a partir da qual foi revisada
  autor_id         bigint NOT NULL REFERENCES usuarios(id),
  revisor_id       bigint REFERENCES usuarios(id),
  aprovador_id     bigint REFERENCES usuarios(id),
  aprovado_em      timestamptz,
  vigencia_inicio  date,
  vigencia_fim     date,
  proxima_revisao  date,
  motivo           text NOT NULL,
  resumo_mudancas  text,
  conteudo         text,                                 -- texto para busca e chat
  arquivo_path     text,                                 -- caminho no repositório privado de arquivos
  arquivo_sha256   char(64) CHECK (arquivo_sha256 ~ '^[0-9a-f]{64}$'),
  criado_em        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (documento_id, maior, menor),
  -- Só rascunhos podem ter numeração v0.x.
  CONSTRAINT aprovada_tem_versao_1 CHECK (estado IN ('rascunho', 'em_revisao') OR maior >= 1),
  -- Versão aprovada tem aprovador e data.
  CONSTRAINT aprovada_tem_aprovador CHECK (
    estado IN ('rascunho', 'em_revisao') OR (aprovador_id IS NOT NULL AND aprovado_em IS NOT NULL)
  ),
  CONSTRAINT vigente_tem_datas CHECK (
    estado <> 'vigente' OR (vigencia_inicio IS NOT NULL AND proxima_revisao IS NOT NULL)
  )
);

-- Uma única versão vigente por código.
CREATE UNIQUE INDEX uma_vigente_por_documento ON versoes (documento_id) WHERE estado = 'vigente';
CREATE INDEX versoes_documento ON versoes (documento_id);

-- Histórico de transições (somente inclusão).
CREATE TABLE transicoes_versao (
  id          bigserial PRIMARY KEY,
  versao_id   bigint NOT NULL REFERENCES versoes(id),
  de          estado_versao,
  para        estado_versao NOT NULL,
  usuario_id  bigint NOT NULL REFERENCES usuarios(id),
  comentario  text,
  em          timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Registros (evidências datadas geradas a partir de formulários)
-- ---------------------------------------------------------------------------
CREATE TABLE registros (
  id                    bigserial PRIMARY KEY,
  codigo                text NOT NULL UNIQUE
                        CHECK (codigo ~ '^TS-REG-[A-Z]{3}-[0-9]{3}-[0-9]{4}-[0-9]{2}-[0-9]{2}(-[0-9]+)?$'),
  formulario_versao_id  bigint NOT NULL REFERENCES versoes(id),
  roteiro_sigla         char(3) REFERENCES roteiros(sigla),
  data                  date NOT NULL,
  descricao             text NOT NULL,
  arquivo_path          text,
  arquivo_sha256        char(64) CHECK (arquivo_sha256 ~ '^[0-9a-f]{64}$'),
  registrado_por        bigint NOT NULL REFERENCES usuarios(id),
  registrado_em         timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Requisitos (cap. 4 a 10) e matriz de evidências
-- ---------------------------------------------------------------------------
CREATE TABLE requisitos (
  id                   bigserial PRIMARY KEY,
  capitulo             int NOT NULL CHECK (capitulo BETWEEN 4 AND 10),
  tema                 text NOT NULL,
  descricao            text,
  edicao               text NOT NULL DEFAULT 'ABNT NBR ISO 21101:2014 + Emenda 1:2024',
  clausula             text,                       -- preenchida só após verificação no texto autorizado
  clausula_verificada  boolean NOT NULL DEFAULT false,
  verificado_por       bigint REFERENCES usuarios(id),
  verificado_em        date,
  CONSTRAINT verificacao_completa CHECK (
    NOT clausula_verificada OR (clausula IS NOT NULL AND verificado_por IS NOT NULL AND verificado_em IS NOT NULL)
  )
);

CREATE TABLE requisito_vinculos (
  id               bigserial PRIMARY KEY,
  requisito_id     bigint NOT NULL REFERENCES requisitos(id),
  documento_id     bigint REFERENCES documentos(id),
  roteiro_sigla    char(3) REFERENCES roteiros(sigla),   -- NULL = todo o SGS
  aplicavel        boolean NOT NULL DEFAULT true,
  justificativa    text NOT NULL,
  situacao         situacao_requisito NOT NULL DEFAULT 'pendente_verificacao',
  responsavel      text,
  proxima_acao     text,
  atualizado_em    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE evidencias (
  id                    bigserial PRIMARY KEY,
  versao_id             bigint NOT NULL REFERENCES versoes(id),   -- versão exata a que se refere
  requisito_vinculo_id  bigint REFERENCES requisito_vinculos(id),
  registro_id           bigint REFERENCES registros(id),
  descricao             text NOT NULL,
  data                  date NOT NULL,
  arquivo_path          text,
  arquivo_sha256        char(64) CHECK (arquivo_sha256 ~ '^[0-9a-f]{64}$'),
  verificada_por        bigint REFERENCES usuarios(id),
  verificada_em         date,
  criado_em             timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT verificacao_completa CHECK ((verificada_por IS NULL) = (verificada_em IS NULL))
);

-- ---------------------------------------------------------------------------
-- Ações, decisões e auditoria
-- ---------------------------------------------------------------------------
CREATE TABLE acoes (
  id                    bigserial PRIMARY KEY,
  origem                origem_acao NOT NULL,
  origem_referencia     text,                      -- ex.: código do registro de incidente
  descricao             text NOT NULL,
  prioridade            prioridade NOT NULL,
  responsavel           text NOT NULL,
  prazo                 date NOT NULL,
  estado                estado_acao NOT NULL DEFAULT 'aberta',
  roteiro_sigla         char(3) REFERENCES roteiros(sigla),
  documento_id          bigint REFERENCES documentos(id),
  evidencia_conclusao   text,
  concluida_em          date,
  eficacia_resultado    text,
  eficacia_verificada_em date,
  criado_em             timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT conclusao_com_evidencia CHECK (
    estado NOT IN ('concluida', 'eficacia_verificada')
    OR (evidencia_conclusao IS NOT NULL AND concluida_em IS NOT NULL)
  ),
  CONSTRAINT eficacia_completa CHECK (
    estado <> 'eficacia_verificada' OR (eficacia_resultado IS NOT NULL AND eficacia_verificada_em IS NOT NULL)
  )
);

CREATE TABLE decisoes (
  id            bigserial PRIMARY KEY,
  descricao     text NOT NULL,
  decidido_por  bigint NOT NULL REFERENCES usuarios(id),
  decidido_em   timestamptz NOT NULL,
  contexto      text,
  referencia    text,     -- documento, ação ou conversa relacionada
  registrado_em timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE auditoria (
  id            bigserial PRIMARY KEY,
  tabela        text NOT NULL,
  registro_id   text,     -- id ou sigla do registro alterado
  operacao      text NOT NULL,
  dados_antes   jsonb,
  dados_depois  jsonb,
  usuario_id    bigint,   -- definido pela aplicação: SET LOCAL sgs.usuario_id = '<id>'
  em            timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Funções e gatilhos
-- ---------------------------------------------------------------------------

-- Trilha de auditoria genérica.
CREATE FUNCTION fn_auditoria() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_usuario bigint := nullif(current_setting('sgs.usuario_id', true), '')::bigint;
  v_antes   jsonb := CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END;
  v_depois  jsonb := CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END;
  v_linha   jsonb := coalesce(v_depois, v_antes);
BEGIN
  INSERT INTO auditoria (tabela, registro_id, operacao, dados_antes, dados_depois, usuario_id)
  VALUES (TG_TABLE_NAME, coalesce(v_linha->>'id', v_linha->>'sigla'), TG_OP, v_antes, v_depois, v_usuario);
  RETURN NULL;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['usuarios','roteiros','documentos','versoes','registros','requisitos',
                           'requisito_vinculos','evidencias','acoes','decisoes']
  LOOP
    EXECUTE format('CREATE TRIGGER trg_auditoria AFTER INSERT OR UPDATE OR DELETE ON %I
                    FOR EACH ROW EXECUTE FUNCTION fn_auditoria()', t);
  END LOOP;
END $$;

-- Tabelas de histórico: somente inclusão.
CREATE FUNCTION fn_somente_inclusao() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'A tabela % só aceita inclusão: o histórico não pode ser alterado nem apagado', TG_TABLE_NAME;
END $$;

CREATE TRIGGER trg_somente_inclusao BEFORE UPDATE OR DELETE ON transicoes_versao
  FOR EACH ROW EXECUTE FUNCTION fn_somente_inclusao();
CREATE TRIGGER trg_somente_inclusao BEFORE UPDATE OR DELETE ON auditoria
  FOR EACH ROW EXECUTE FUNCTION fn_somente_inclusao();
CREATE TRIGGER trg_somente_inclusao BEFORE UPDATE OR DELETE ON decisoes
  FOR EACH ROW EXECUTE FUNCTION fn_somente_inclusao();
-- Registros não são apagados; correções viram novo registro.
CREATE TRIGGER trg_registro_sem_exclusao BEFORE DELETE ON registros
  FOR EACH ROW EXECUTE FUNCTION fn_somente_inclusao();

-- Versões: nunca apagar; estado e conteúdo só mudam pelas regras abaixo.
CREATE FUNCTION fn_protege_versao() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Versões não podem ser apagadas; use o estado Arquivado';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.estado <> 'rascunho' OR NEW.aprovador_id IS NOT NULL OR NEW.aprovado_em IS NOT NULL
       OR NEW.vigencia_inicio IS NOT NULL OR NEW.vigencia_fim IS NOT NULL THEN
      RAISE EXCEPTION 'Toda versão nasce como Rascunho, sem aprovação nem vigência';
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE
  IF NEW.documento_id <> OLD.documento_id OR NEW.autor_id <> OLD.autor_id THEN
    RAISE EXCEPTION 'Uma versão não pode mudar de documento nem de autor';
  END IF;

  -- Dentro de sgs_transicionar() as mudanças já foram validadas.
  IF coalesce(current_setting('sgs.transicao', true), '') = 'on' THEN
    RETURN NEW;
  END IF;

  IF NEW.estado IS DISTINCT FROM OLD.estado THEN
    RAISE EXCEPTION 'O estado de uma versão só muda pela função sgs_transicionar()';
  END IF;

  -- Fora de Rascunho, a versão fica congelada.
  IF OLD.estado <> 'rascunho' THEN
    RAISE EXCEPTION 'Versão em estado % não pode ser alterada; crie uma nova versão', OLD.estado;
  END IF;

  -- Em Rascunho, aprovação, vigência e numeração só mudam pelo fluxo.
  IF (NEW.aprovador_id, NEW.aprovado_em, NEW.vigencia_inicio, NEW.vigencia_fim, NEW.maior, NEW.menor)
     IS DISTINCT FROM
     (OLD.aprovador_id, OLD.aprovado_em, OLD.vigencia_inicio, OLD.vigencia_fim, OLD.maior, OLD.menor) THEN
    RAISE EXCEPTION 'Aprovação, vigência e numeração só mudam pela função sgs_transicionar()';
  END IF;

  RETURN NEW;
END $$;

CREATE TRIGGER trg_protege_versao BEFORE INSERT OR UPDATE OR DELETE ON versoes
  FOR EACH ROW EXECUTE FUNCTION fn_protege_versao();

-- Ao criar uma versão, registra a transição inicial.
CREATE FUNCTION fn_versao_criada() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO transicoes_versao (versao_id, de, para, usuario_id, comentario)
  VALUES (NEW.id, NULL, 'rascunho', NEW.autor_id, 'Versão criada');
  RETURN NULL;
END $$;

CREATE TRIGGER trg_versao_criada AFTER INSERT ON versoes
  FOR EACH ROW EXECUTE FUNCTION fn_versao_criada();

-- Registro só pode vir de um formulário (FOR) aprovado/vigente.
CREATE FUNCTION fn_valida_registro() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_tipo text; v_estado estado_versao;
BEGIN
  SELECT d.tipo, v.estado INTO v_tipo, v_estado
    FROM versoes v JOIN documentos d ON d.id = v.documento_id
   WHERE v.id = NEW.formulario_versao_id;
  IF v_tipo <> 'FOR' THEN
    RAISE EXCEPTION 'Registro deve apontar para a versão de um formulário (FOR), não %', v_tipo;
  END IF;
  IF v_estado NOT IN ('vigente', 'substituido') THEN
    RAISE EXCEPTION 'Registro só pode usar formulário vigente (ou substituído, para registros antigos); estado atual: %', v_estado;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_valida_registro BEFORE INSERT OR UPDATE ON registros
  FOR EACH ROW EXECUTE FUNCTION fn_valida_registro();

-- "Implementação comprovada" exige ao menos uma evidência verificada.
CREATE FUNCTION fn_valida_situacao_requisito() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.atualizado_em := now();
  IF NEW.situacao = 'implementacao_comprovada' AND NOT EXISTS (
       SELECT 1 FROM evidencias e
        WHERE e.requisito_vinculo_id = NEW.id AND e.verificada_em IS NOT NULL) THEN
    RAISE EXCEPTION 'Implementação comprovada exige evidência verificada vinculada';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_valida_situacao_requisito BEFORE INSERT OR UPDATE ON requisito_vinculos
  FOR EACH ROW EXECUTE FUNCTION fn_valida_situacao_requisito();

-- Transição de estado de uma versão (única porta de entrada para mudar estado).
CREATE FUNCTION sgs_transicionar(
  p_versao_id  bigint,
  p_para       estado_versao,
  p_usuario_id bigint,
  p_comentario text DEFAULT NULL,
  p_vigencia   date DEFAULT NULL
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v        versoes%ROWTYPE;
  v_papel  papel_usuario;
  v_ativo  boolean;
  v_ant    versoes%ROWTYPE;
  v_ok     boolean := false;
BEGIN
  SELECT * INTO v FROM versoes WHERE id = p_versao_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Versão % não encontrada', p_versao_id; END IF;

  SELECT papel, ativo INTO v_papel, v_ativo FROM usuarios WHERE id = p_usuario_id;
  IF NOT FOUND OR NOT v_ativo THEN RAISE EXCEPTION 'Usuário % inexistente ou inativo', p_usuario_id; END IF;

  IF v_papel IN ('agente_ia', 'equipe_campo', 'leitura') THEN
    RAISE EXCEPTION 'O papel % não pode mudar o estado de versões', v_papel;
  END IF;

  -- Transições permitidas e papéis autorizados.
  v_ok := CASE
    WHEN v.estado = 'rascunho'    AND p_para = 'em_revisao'
      THEN v_papel IN ('autor', 'revisor', 'aprovador', 'admin_sgs')
    WHEN v.estado = 'em_revisao'  AND p_para = 'rascunho'
      THEN v_papel IN ('revisor', 'aprovador', 'admin_sgs')
    WHEN v.estado = 'em_revisao'  AND p_para = 'aprovado'
      THEN v_papel IN ('aprovador', 'admin_sgs')
    WHEN v.estado = 'aprovado'    AND p_para = 'vigente'
      THEN v_papel IN ('aprovador', 'admin_sgs')
    WHEN v.estado IN ('vigente', 'substituido', 'aprovado') AND p_para = 'arquivado'
      THEN v_papel IN ('aprovador', 'admin_sgs')
    ELSE false
  END;

  IF NOT v_ok THEN
    RAISE EXCEPTION 'Transição % → % não permitida para o papel %', v.estado, p_para, v_papel;
  END IF;

  PERFORM set_config('sgs.transicao', 'on', true);
  PERFORM set_config('sgs.usuario_id', p_usuario_id::text, true);

  IF p_para = 'em_revisao' THEN
    UPDATE versoes SET estado = 'em_revisao',
           revisor_id = coalesce(revisor_id, CASE WHEN v_papel <> 'autor' THEN p_usuario_id END)
     WHERE id = v.id;

  ELSIF p_para = 'rascunho' THEN
    UPDATE versoes SET estado = 'rascunho' WHERE id = v.id;

  ELSIF p_para = 'aprovado' THEN
    -- Primeira aprovação de um v0.x vira v1.0.
    UPDATE versoes SET estado = 'aprovado',
           maior = CASE WHEN maior = 0 THEN 1 ELSE maior END,
           menor = CASE WHEN maior = 0 THEN 0 ELSE menor END,
           aprovador_id = p_usuario_id,
           aprovado_em  = now()
     WHERE id = v.id;

  ELSIF p_para = 'vigente' THEN
    -- Troca de vigência na mesma transação: a anterior vira Substituído.
    SELECT * INTO v_ant FROM versoes
     WHERE documento_id = v.documento_id AND estado = 'vigente' FOR UPDATE;
    IF FOUND THEN
      UPDATE versoes SET estado = 'substituido', vigencia_fim = coalesce(p_vigencia, current_date)
       WHERE id = v_ant.id;
      INSERT INTO transicoes_versao (versao_id, de, para, usuario_id, comentario)
      VALUES (v_ant.id, 'vigente', 'substituido', p_usuario_id,
              'Substituída pela versão ' || (SELECT versao FROM versoes WHERE id = v.id));
    END IF;
    UPDATE versoes SET estado = 'vigente',
           vigencia_inicio = coalesce(p_vigencia, current_date),
           proxima_revisao = coalesce(proxima_revisao, coalesce(p_vigencia, current_date) + interval '12 months')
     WHERE id = v.id;

  ELSIF p_para = 'arquivado' THEN
    UPDATE versoes SET estado = 'arquivado',
           vigencia_fim = CASE WHEN v.estado = 'vigente' THEN current_date ELSE vigencia_fim END
     WHERE id = v.id;
  END IF;

  INSERT INTO transicoes_versao (versao_id, de, para, usuario_id, comentario)
  VALUES (v.id, v.estado, p_para, p_usuario_id, p_comentario);

  PERFORM set_config('sgs.transicao', 'off', true);
END $$;

-- Nova versão a partir de outra (revisão ou recuperação de versão antiga).
-- Sempre nasce como Rascunho e passa por todo o ciclo de aprovação.
CREATE FUNCTION sgs_nova_versao(
  p_base_versao_id bigint,
  p_autor_id       bigint,
  p_motivo         text,
  p_mudanca_maior  boolean DEFAULT true
) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
  b       versoes%ROWTYPE;
  v_maior int;
  v_menor int;
  v_id    bigint;
BEGIN
  SELECT * INTO b FROM versoes WHERE id = p_base_versao_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Versão-base % não encontrada', p_base_versao_id; END IF;

  SELECT max(maior) INTO v_maior FROM versoes WHERE documento_id = b.documento_id;
  IF p_mudanca_maior OR v_maior = 0 THEN
    v_maior := v_maior + 1; v_menor := 0;
  ELSE
    SELECT max(menor) + 1 INTO v_menor FROM versoes
     WHERE documento_id = b.documento_id AND maior = v_maior;
  END IF;

  INSERT INTO versoes (documento_id, maior, menor, base_versao_id, autor_id, motivo, conteudo)
  VALUES (b.documento_id, v_maior, v_menor, b.id, p_autor_id, p_motivo, b.conteudo)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- ---------------------------------------------------------------------------
-- Visões para consulta
-- ---------------------------------------------------------------------------
CREATE VIEW v_documentos_vigentes AS
SELECT d.codigo, d.titulo, d.tipo, coalesce(d.roteiro_sigla, 'GER') AS escopo,
       v.versao, v.vigencia_inicio, v.proxima_revisao, d.classificacao, v.id AS versao_id, d.id AS documento_id
  FROM documentos d JOIN versoes v ON v.documento_id = d.id AND v.estado = 'vigente';

-- Lista mestra: todos os documentos, com a versão vigente e a mais recente em andamento.
CREATE VIEW v_lista_mestra AS
SELECT d.codigo, d.titulo, d.tipo, coalesce(d.roteiro_sigla, 'GER') AS escopo, d.responsavel_funcao,
       vg.versao AS versao_vigente, vg.vigencia_inicio, vg.proxima_revisao,
       (SELECT v.versao || ' (' || v.estado || ')' FROM versoes v
         WHERE v.documento_id = d.id AND v.estado IN ('rascunho', 'em_revisao', 'aprovado')
         ORDER BY v.maior DESC, v.menor DESC LIMIT 1) AS versao_em_andamento
  FROM documentos d
  LEFT JOIN versoes vg ON vg.documento_id = d.id AND vg.estado = 'vigente';

CREATE VIEW v_revisoes_a_vencer AS
SELECT codigo, titulo, escopo, versao, proxima_revisao,
       (proxima_revisao - current_date) AS dias_restantes
  FROM v_documentos_vigentes
 WHERE proxima_revisao <= current_date + 30;

CREATE VIEW v_acoes_atrasadas AS
SELECT id, origem, descricao, prioridade, responsavel, prazo, estado, roteiro_sigla,
       (current_date - prazo) AS dias_atraso
  FROM acoes
 WHERE estado IN ('aberta', 'em_andamento') AND prazo < current_date;

INSERT INTO schema_migrations (versao) VALUES ('001_esquema_inicial');

COMMIT;
