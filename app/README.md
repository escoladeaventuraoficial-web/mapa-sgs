# Aplicação do SGS

## Banco de dados (PostgreSQL 14+)

| Caminho | Conteúdo |
|---|---|
| `db/migrations/` | Esquema: documentos, versões, transições, registros, requisitos, evidências, ações, decisões, auditoria. |
| `db/seed/001_referencia.sql` | Tipos de documento, roteiro piloto (PDF – Poço de Ferro), temas dos capítulos 4 a 10. |
| `db/seed/002_demo_ficticio.sql` | **Dados fictícios** para demonstração (roteiro TST, e-mails `.invalid`). Não rodar em produção. |
| `db/tests/` | Testes das regras do padrão. |
| `db/run-tests.sh` | Cria um banco temporário, aplica tudo e roda os testes. |

### Regras garantidas pelo banco

- Código `TS-TIPO-ESCOPO-NNN` coerente com tipo e roteiro; registros (REG) ficam em tabela própria.
- Toda versão nasce como Rascunho. O estado só muda pela função `sgs_transicionar()`, que valida a transição e o papel do usuário.
- O papel `agente_ia` só cria rascunhos; não muda estados.
- Primeira aprovação de um `v0.x` vira `v1.0`.
- Uma única versão Vigente por código (índice único). A troca de vigência marca a anterior como Substituído na mesma transação.
- Versão fora de Rascunho não pode ser editada nem apagada. Recuperar texto antigo = `sgs_nova_versao()`, com ciclo completo.
- Transições, decisões e auditoria são somente inclusão.
- Registro precisa apontar para a versão de um formulário (FOR) vigente.
- "Implementação comprovada" exige evidência verificada.
- Ação concluída exige evidência de conclusão; eficácia verificada exige resultado e data.

Visões: `v_documentos_vigentes`, `v_lista_mestra`, `v_revisoes_a_vencer` (30 dias), `v_acoes_atrasadas`.

### Rodar os testes

```bash
DATABASE_URL=postgres://postgres@localhost:5432/postgres app/db/run-tests.sh
```

### Instalar um banco novo

```bash
createdb sgs
for f in app/db/migrations/*.sql app/db/seed/001_referencia.sql; do psql sgs -v ON_ERROR_STOP=1 -f "$f"; done
# Somente em ambiente de teste:
psql sgs -v ON_ERROR_STOP=1 -f app/db/seed/002_demo_ficticio.sql
```

### Backup e restauração

```bash
# Backup (banco + metadados + trilha de auditoria)
pg_dump -Fc sgs > backups/sgs_$(date +%F).dump
# Os arquivos originais ficam em $ARQUIVOS_DIR: copie a pasta junto com o dump.

# Restauração em um banco vazio
createdb sgs_restaurado
pg_restore -d sgs_restaurado backups/sgs_AAAA-MM-DD.dump
```

Teste a restauração periodicamente em um banco separado antes de confiar no backup.
