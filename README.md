# SGS Turismo

Plataforma de Sistemas de Gestão da Segurança (SGS) por produto da Trilhas do Sul,
com o mapa interativo da ABNT NBR ISO 21101 (turismo de aventura).
O site é o arquivo `index.html`, publicado em sgsturismo.com.br.

## Como funciona

- **Tela inicial (`#/`)**: lista os produtos (roteiros) em cartões, com progresso, busca e o botão **Novo produto**.
  O Poço de Ferro é o piloto; os demais produtos de exemplo são fictícios e podem ser excluídos.
- **SGS do produto (`#/p/<id>`)**: abre o mapa da norma daquele produto, com o botão **Produtos** para voltar.
- **Separação dos dados** (decisão de 20/11/2026): documentos da empresa (contexto, política, funções,
  auditoria etc.) são únicos e valem para todos os produtos; documentos e registros de operação
  (contexto da atividade, inventário de perigos, procedimentos, competência do participante, termo, PAE,
  ficha, check-lists, simulados, incidentes, feedback) ficam separados por produto (`PROD_REFS` no código).
- Enquanto não há servidor, produtos e progresso ficam no `localStorage` do navegador
  (`sgs-produtos-v1`, `sgs-itens-empresa-v1`, `sgs-itens-produto-v1:<id>`). O progresso do mapa antigo
  (`sgs-mapa-itens-v1`) é migrado na primeira abertura: itens da empresa para a empresa, itens de operação
  para o Poço de Ferro.
