---
name: spec-task
description: Redige, em conversa com o usuário, a especificação completa de uma task para um desenvolvedor humano implementar (não um plano prescritivo para o Cursor). Produz o texto pronto para colar na descrição do Work Item no Azure Boards, incluindo a área de impacto que habilita a checagem de conflito entre devs. Use quando o usuário pedir "/spec-task" ou quiser criar/detalhar uma task para distribuir ao time.
argument-hint: "descrição breve da funcionalidade, ou nº/slug de uma ideia já iniciada (opcional)"
disable-model-invocation: true
---

Ajuda o usuário a especificar uma task **para um desenvolvedor implementar por conta própria** — diferente de um `.cursor/plans/*.plan.md`, que é prescritivo passo-a-passo para o Cursor executar. Aqui a spec descreve **o quê** e **por quê**, com critério de aceite testável; o **como** fica com o dev. Ver ADR-0039 (`docs/adr/0039-team-scaling-task-spec-and-review-workflow.md` no repo do projeto).

## 0. Como conduzir a conversa (disciplina da skill `grilling`)

Levantar o conteúdo (passo 1) e resolver conflitos de arquitetura (passo 2) segue a mesma disciplina da skill `grilling`, aplicada ao design da task em vez de a um plano de código:

- **Quem decide o quê:** siga o contrato de aprovação da skill `plan-task` (`references/owner-approval.md` dela). As perguntas do usuário vão uma por vez; as decisões de classe owner vão num único pedido de aprovação em lote.
- **Uma pergunta por vez ao usuário.** Nunca acumule várias perguntas num só turno — é confuso. Espere a resposta antes de seguir para a próxima.
- **Sempre traga uma recomendação.** Para cada pergunta, já venha com sua resposta sugerida (e o porquê) — quem decide não parte do zero.
- **Fato é seu trabalho; decisão é do usuário ou do owner, conforme o contrato.** Se algo pode ser respondido explorando o código/docs (ex.: "esse guard já existe?", "esse campo já é real ou mock?"), vá lá e descubra — não pergunte. Só vire pergunta o que é genuinamente uma escolha (trade-off, prioridade, corte de escopo).
- **Percorra a árvore de dependências.** Resolva uma decisão por vez, na ordem em que uma depende da outra — não pule pra uma decisão que depende de uma resposta ainda em aberto.
- **Não finalize sem entendimento compartilhado.** Só execute o passo 4 (criar Work Item + gravar o arquivo) depois que as perguntas abertas dos passos 1-2 estiverem resolvidas, o usuário tiver confirmado e cada decisão de classe owner estiver aprovada ou pré-aprovada pelo usuário. Todas as decisões tomadas, as do usuário e as do owner, entram na seção "Decisões" da spec, conforme o contrato. Uma pré-aprovada entra com o estado `pendente do owner`. Se um conflito de arquitetura aparecer no meio do caminho (passo 2), pare e resolva antes de continuar — não empurre a decisão pra dentro da spec como ressalva e siga em frente.

## 1. Levantar o conteúdo com o usuário

Pergunte (ou extraia do argumento, se dado) o suficiente para preencher:

- **Objetivo** — o que a task entrega, em 1-2 frases.
- **Contexto/motivação** — por que agora, que problema resolve. Se vier de um item já registrado (varredura de fechamento, gap de acceptance-criteria, ADR pendente), cite a fonte.
- **Escopo** — o que está dentro e o que está explicitamente fora (evita que o dev "melhore" além do pedido).
- **Critério de aceite** — lista numerada, cada item testável (comportamento observável, não implementação).
- **Área de impacto esperada** — módulos/projetos/endpoints que a task deve tocar. **Não é opcional**: é a base da checagem de conflito entre devs (ADR-0039 §4).

## 2. Ancorar na arquitetura vigente

Antes de finalizar, confira contra a hierarquia de fontes (`CLAUDE.md` §3): ADRs relacionados ao domínio tocado, rules do Cursor relevantes à área (`.cursor/rules/005-documentation-context-hierarchy.mdc` despacha por área), e o `scope.md`/`acceptance-criteria.md` da release corrente. Cite os ADRs/rules aplicáveis na spec — o dev que só olha o Work Item precisa saber onde procurar as regras do jogo, já que ele não lê `.cursor/rules/*` com a curadoria automática que o Cursor recebe.

**Se a task pedida conflitar com uma decisão já fixada em ADR** (ex.: automação vedada por um ADR, mudança de stack implícita) **— pare e aplique a skill `domain-modeling`**: isso é uma decisão do owner (grilling, um item por vez — §0), não algo para contornar em silêncio ou anotar como ressalva na spec. O critério de "quando oferecer ADR" da `domain-modeling` (difícil de reverter + surpreendente sem contexto + resultado de trade-off real) decide se o conflito vira emenda a um ADR existente, ADR novo, ou redução de escopo da task — apresente as opções ao owner como a `domain-modeling` faria, não decida sozinho.

## 3. Checar conflito com o que já está em andamento

Consulte o Azure Boards diretamente via MCP — `wit_query` com `action: "wiql"` e a query no parâmetro `wiql` — para saber quais tasks estão em andamento agora; não dependa da memória do usuário.

**O estado real está em `[System.BoardColumn]`, não em `[System.State]`.** Neste board, `Requirement` fica com `System.State = "Active"` em **qualquer** coluna a partir de Ready-to-work; filtrar por `State` devolve tasks que ninguém pegou e faz tratar como intocável uma spec que ainda é editável. Peça a coluna e julgue por ela:

```sql
SELECT [System.Id], [System.Title], [System.BoardColumn], [System.AssignedTo]
FROM WorkItems
WHERE [System.TeamProject] = @project AND [System.State] = 'Active'
```

Só as colunas **depois** de Ready-to-work contam como "alguém já está mexendo" — até Ready-to-work a spec ainda é editável sem comunicar o dev. Se o MCP estiver indisponível na sessão, aí sim pergunte ao usuário. Para cada task retornada, confira a área de impacto declarada dela (leia o `backlog/tasks/<id>-*.md` correspondente) contra a área da task nova; se houver branch ativa identificável, reforce comparando `git diff master..<branch> --stat`. Sobreposição não é proibitiva — pode virar dependência explícita (predecessor/blocked by no Azure Boards) em vez de bloqueio.

## 4. Produzir a spec — arquivo no repo é a fonte, Work Item é a projeção

Por decisão do ADR-0039 (`docs/adr/0039-team-scaling-task-spec-and-review-workflow.md` no repo do projeto) §1, a spec vive em **dois lugares com o mesmo conteúdo**, mas um é a fonte:

1. **Crie o Work Item via MCP** — `wit_work_item_write` com `action: "create"`, `project`, `workItemType` (conforme o board) e `fields` (lista de `{name, value}`, ex.: `System.Title`, `System.Description` com `format: "Markdown"`) — com o título e o conteúdo da spec na descrição — isso dá o ID definitivo usado no nome do arquivo. Se o MCP estiver indisponível na sessão, avise o usuário para criar manualmente e informar o ID antes de gravar o arquivo.
2. **Grave o arquivo em `backlog/tasks/<id-do-work-item>-<slug>.md`** (crie a pasta se não existir) usando o ID retornado — esta é a referência canônica; é contra ela que o `/audit-task` audita quando os dois divergirem.
3. Se editar a spec depois de criada, atualize o Work Item também — `wit_work_item_write` com `action: "update"`, `id` e `updates` (lista de `{op, path, value}`, ex.: `path: "/fields/System.Description"`) — para manter os dois em sincronia — o arquivo do repo continua sendo a fonte em caso de divergência.

Formato (idêntico nos dois lugares):

```md
# {ID do Work Item, se já existir} — {título curto}

## Objetivo
{1-2 frases}

## Contexto
{motivação, fonte se houver}

## Escopo
**Dentro:** {...}
**Fora:** {...}

## Critérios de aceite
1. {testável}
2. {testável}
...

## Área de impacto esperada
{módulos/projetos/endpoints}

## Referências de arquitetura
{ADRs e rules aplicáveis, com link relativo}

## Decisões
| ID | Resumo | Classe | Estado |
|---|---|---|---|
{índice de todas as decisões da especificação, as do usuário e as do owner; abaixo da tabela, um bloco autoexplicativo por decisão (problema, decisão, motivo, alternativas, impacto, incertezas), no formato do contrato de aprovação}
```

A seção "Decisões" é o registro exclusivo das decisões da task, por pedido do owner. O Work Item é a fonte de verdade e de consulta dessa seção; o espelho e os planos são cópias que citam o ID (`D1`, `D2`…), e em divergência vale o Work Item.

**Submissão ao owner.** Com qualquer decisão `pendente do owner`, a spec pode ser criada no board, mas fica **sem responsável** até a aprovação (contrato de aprovação). Por pedido do usuário, submeta por um destes canais:
- **Comentário na WI**, com a tabela do pedido de aprovação;
- **PR em rascunho**, só com o `backlog/tasks/<id>-<slug>.md` commitado e a tabela na descrição.

Quando o owner responder, atualize os estados no arquivo e no Work Item.

Não inclua passos de implementação, escolha de algoritmo ou nomes de classes/métodos a criar — isso é decisão do dev. Se o usuário insistir em detalhar "como", pergunte se não é o caso de ele mesmo pegar a task no modo "terceiro dev" (spec vira plano do Cursor, fluxo `/execute`+`/revise` de sempre).

## 5. Lembrete final

Diga ao usuário:

- Nomeie a branch referenciando o ID do Work Item (ex. `feature/wi-1234-slug-curto`) — é o que habilita rastreabilidade e a checagem de conflito por diff mais adiante, no `/audit-task`.
- Se editar a spec depois (no Work Item ou no arquivo), atualize os dois — o arquivo do repo é o que conta em caso de divergência, mas deixar o Work Item desatualizado confunde quem só olha o board.
- Se houver decisões `pendente do owner`, liste-as e diga por qual canal elas vão ao owner. A task só é atribuível depois da aprovação.
