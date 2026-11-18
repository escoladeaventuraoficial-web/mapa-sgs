> **RASCUNHO** – aguardando aprovação formal

| Trilhas do Sul · SGS | **Controle de documentos e registros** |
|---|---|
| Código | TS-PG-GER-001 |
| Versão | v0.1 |
| Estado | Em revisão |
| Tipo | PG – Procedimento de gestão |
| Escopo | GER – todo o SGS |
| Vínculo normativo | ABNT NBR ISO 21101:2014 + Emenda 1:2024, cap. 7 – informação documentada (cláusula exata pendente de verificação no texto autorizado) |
| Origem da obrigação | Norma |
| Responsável (dono) | Responsável pelo SGS |

**Bloco de controle**

| Autor | Revisor | Aprovador | Data de aprovação | Início de vigência | Próxima revisão |
|---|---|---|---|---|---|
| Agente de IA do SGS | Vagner Fagundes | Vagner Fagundes | pendente | pendente | 12 meses após a vigência |

**Histórico de revisões**

| Versão | Data | Motivo | Aprovador |
|---|---|---|---|
| v0.1 | 18/11/2026 | Criação do padrão no início do novo SGS. Proposta aceita por Vagner para início dos trabalhos; aprovação formal (v1.0) pendente. | — |

---

## 1. Objetivo

Definir como os documentos e registros do SGS da Trilhas do Sul são codificados, identificados, versionados, aprovados, distribuídos e arquivados, para que a equipe use sempre a versão vigente e o histórico fique preservado.

## 2. Codificação

Todo documento recebe um código estável no formato `TS-TIPO-ESCOPO-NNN`. O código não muda entre versões e nunca é reaproveitado.

- **TS**: Trilhas do Sul.
- **TIPO**: sigla da tabela da seção 3.
- **ESCOPO**: `GER` para documentos do sistema inteiro, ou a sigla de 3 letras do roteiro. Roteiros cadastrados: `PDF` = Poço de Ferro. Novos roteiros recebem sigla quando o responsável pelo SGS os confirmar no escopo.
- **NNN**: sequencial por tipo e escopo, a partir de 001.

Exemplos: `TS-POL-GER-001` (Política de Segurança), `TS-AR-PDF-001` (Avaliação de Riscos do Poço de Ferro), `TS-PAE-PDF-001` (PAE do Poço de Ferro).

Registros usam o código do formulário que os gerou + data: `TS-REG-PDF-001-2026-12-05`. Se houver mais de um no mesmo dia, acrescenta-se `-2`, `-3`.

## 3. Tipos de documento

| Sigla | Tipo | O que é | Escopo usual |
|---|---|---|---|
| MAN | Manual | Manual do SGS: escopo, estrutura, mapa dos documentos | GER |
| POL | Política | Política de segurança e compromissos da direção | GER |
| PG | Procedimento de gestão | Como o SGS funciona: documentos, auditoria, ações corretivas, análise crítica | GER |
| PO | Procedimento operacional | Como a atividade é conduzida em campo | Roteiro |
| IT | Instrução de trabalho | Passo a passo de uma tarefa específica | Roteiro ou GER |
| AR | Inventário de perigos e avaliação de riscos | Perigos, riscos, controles e risco residual | Roteiro |
| PAE | Plano de Atendimento a Emergências | Cenários, responsabilidades, contatos, rotas de evacuação | Roteiro |
| PLA | Plano | Objetivos, programa de simulados, de auditorias, de capacitação | GER |
| FOR | Formulário / modelo | Modelo em branco a ser preenchido | Roteiro ou GER |
| REG | Registro | Formulário preenchido; evidência datada, sem versões | Roteiro ou GER |
| INF | Informação ao participante | Briefing, termo de conhecimento de riscos, orientações | Roteiro |
| LIS | Lista | Lista mestra, requisitos legais, fornecedores, equipamentos | GER |

## 4. Metadados

Cada documento tem um **cadastro** (dados que não mudam) e um **registro por versão** (dados de cada revisão).

| Campo | Nível | Obrigatório |
|---|---|---|
| Código | Documento | Sim |
| Título | Documento | Sim |
| Tipo | Documento | Sim |
| Roteiro / escopo | Documento | Sim |
| Vínculo normativo (capítulo; cláusula quando verificada) | Documento | Sim |
| Origem da obrigação: norma, requisito legal, regra interna ou recomendação | Documento | Sim |
| Responsável (função) | Documento | Sim |
| Versão | Versão | Sim |
| Estado | Versão | Sim |
| Autor, revisor, aprovador e data de aprovação | Versão | Sim |
| Início de vigência e próxima revisão | Versão | Sim |
| Motivo e resumo das mudanças | Versão | Sim |
| Arquivo original e hash (gerado pelo sistema) | Versão | Sim |
| Documentos relacionados (código + versão) | Versão | Não |

## 5. Cabeçalho, bloco de controle e rodapé

Use o modelo em [`modelos/MODELO-DOCUMENTO.md`](../../modelos/MODELO-DOCUMENTO.md).

- **Cabeçalho** (toda página): logotipo · título · código · versão · estado · página X de Y.
- **Bloco de controle** (primeira página): autor, revisor, aprovador, data de aprovação, início de vigência, próxima revisão e histórico de revisões.
- **Rodapé** (toda página): "Documento controlado. Cópia impressa não é controlada: confira a versão vigente no sistema." · classificação de acesso (Interno ou Equipe de campo).
- Rascunhos e versões substituídas levam marca d'água "RASCUNHO" ou "SUBSTITUÍDO" em toda página.

## 6. Estados e fluxo

```
Rascunho → Em revisão → Aprovado → Vigente → Substituído → Arquivado
              │                       │
              └→ Rascunho (ajustes)   └→ Arquivado (retirado sem substituto)
```

| Estado | Significado | Quem muda para este estado |
|---|---|---|
| Rascunho | Em elaboração (v0.x ou nova versão em preparo) | Autor (inclusive o Agente de IA) |
| Em revisão | Enviado ao revisor | Autor |
| Aprovado | Aprovado, aguardando data de vigência | Aprovador |
| Vigente | Versão em uso; **só uma por código** | Aprovador ou sistema na data de vigência |
| Substituído | Substituído por versão mais nova; só consulta | Sistema, ao tornar vigente a nova versão |
| Arquivado | Fora de uso, guardado pelo prazo definido | Aprovador |

Regras:

1. A troca de vigência ocorre numa única transação: a nova versão vira Vigente e a anterior vira Substituído.
2. O histórico nunca é apagado. Cada transição registra quem, quando e comentário.
3. Recuperar uma versão antiga exige uma nova versão com ciclo completo de aprovação.
4. O Agente de IA só cria Rascunhos e propostas. Aprovação e vigência são de pessoas autorizadas.
5. Na fase inicial, o aprovador de todos os documentos é o responsável pelo SGS (Vagner Fagundes).

## 7. Numeração de versões

- `v0.1`, `v0.2`…: rascunhos antes da primeira aprovação.
- `v1.0`: primeira versão aprovada.
- Mudança de conteúdo (risco, controle, responsabilidade, procedimento): sobe o número principal (`v2.0`).
- Correção sem efeito na operação (digitação, formatação): sobe o decimal (`v1.1`), com revisão simplificada, mas ainda aprovada.

## 8. Revisão

- Revisão obrigatória a cada 12 meses a partir da vigência.
- Revisão antecipada quando houver mudança na operação, infraestrutura, equipe, análise de riscos, PAE ou requisitos aplicáveis, ou após incidente, quase acidente ou simulado que afete o documento.
- Toda proposta de revisão informa: versão-base, motivo, mudanças, roteiros e documentos afetados, evidências a atualizar.

## 9. Registros e evidências

- Registros (`REG`) não têm versões. Depois de assinados, só são arquivados.
- Cada registro aponta a versão exata do formulário que o gerou e o roteiro.
- Na matriz de requisitos, a situação de cada requisito é: **Elaborado**, **Aprovado**, **Implementação comprovada** ou **Pendente de verificação**. Implementação comprovada exige evidência verificável.

## 10. Organização

- **Por requisito**: matriz dos capítulos 4 a 10 da ISO 21101, cada linha ligada a documento, versão, evidência, responsável, situação e próxima ação.
- **Por roteiro**: kit mínimo de cada roteiro: ficha do roteiro, AR, PO e IT, PAE, INF, FOR e REG.

## 11. Nome de arquivo e pastas

- Nome: `CÓDIGO_vX.Y_Titulo-curto`, ex.: `TS-PAE-PDF-001_v1.0_PAE-Poco-de-Ferro.docx`.
- Pastas (enquanto o sistema não estiver em uso):

```
00_Padrao/          padrão e modelos
01_Gestao_GER/      MAN, POL, PG, PLA, LIS
02_Roteiros/PDF_Poco_de_Ferro/   AR, PO, IT, PAE, INF, FOR
03_Registros/PDF_Poco_de_Ferro/  inspeções, simulados, incidentes
04_Obsoletos/       versões substituídas e arquivadas
```

---

Documento controlado. Cópia impressa não é controlada: confira a versão vigente no sistema. · Classificação: Interno
