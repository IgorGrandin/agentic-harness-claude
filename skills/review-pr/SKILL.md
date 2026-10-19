---
name: review-pr
description: Revisa um pull request do Azure DevOps aberto por um dev da equipe — audita o diff real contra as rules, ADRs e o escopo da release, aplica a rubrica de auditoria da casa, emite veredicto (conforme / com ressalvas / não conforme) e, com aval do usuário, comenta no PR e registra o achado. Use quando o usuário pedir "/review-pr <número>".
argument-hint: "número do PR (ex.: 1003)"
disable-model-invocation: true
---

Audita um PR de dev da equipe **antes do merge**. Irmã do `/revise` (que audita ciclos `/execute` do Cursor), com a mesma postura: **não confia na descrição do PR — verifica**. A diferença é a origem do trabalho (dev humano, via Azure DevOps) e o fato de que o desfecho é um **comentário no PR**, não um build-log.

## 0. Coordenadas do repositório

Azure DevOps via MCP — organização `confitecDevOps`, projeto `brixbroker`, repositório `brixbroker`. As ferramentas são **orientadas a `action`**, não uma por operação:

| Ferramenta | `action` | Para quê |
|---|---|---|
| `azure-devops:repo_pull_request` | `get` · `list` · `list_by_commits` | dados do PR; `get` aceita `includeChangedFiles`, `includeWorkItemRefs`, `includeLabels` |
| `azure-devops:repo_pull_request_thread` | `list` · `list_comments` | ler threads e comentários |
| `azure-devops:repo_pull_request_thread_write` | `create` · `reply` · `update_status` | comentar no PR |
| `azure-devops:repo_file` | `get_content` · `list_directory` | conteúdo de arquivo numa branch/commit |
| `azure-devops:pipelines_build` | `list` · `get_status` · `get_changes` | evidência de gate no CI |

`repositoryId` e `pullRequestId` são obrigatórios nas de PR; `project` é obrigatório sempre que `repositoryId` for **nome** em vez de GUID (é o nosso caso: `brixbroker`/`brixbroker`). `azure-devops:pipelines_build` exige `project`.

**Atenção ao mecânico:** nenhuma dessas ferramentas devolve **conteúdo de diff** — `includeChangedFiles` dá só a lista de arquivos. De onde vem o diff real: §3.

## 1. Situar o PR antes de ler código

Busque o PR pelo número passado (`includeChangedFiles`, `includeWorkItemRefs`) e liste as threads. Antes de qualquer julgamento técnico, estabeleça:

- **Status.** `status: 1` = **aberto** (revisão é tempestiva, dá para barrar); `3` = já **completado** (a revisão vira registro/evolutiva, mude o tom — não adianta "bloquear" o que já entrou). Cuidado: `lastMergeCommit` existe mesmo em PR aberto (é a prévia de merge) — **não** é prova de que mergeou.
- **Quem falta aprovar** e se há política obrigatória pendente.
- **Branch e task.** A convenção de branch (ID do Work Item + área de impacto) e o processo de spec/revisão são do **ADR-0039** — abra-o. Branch sem ID e PR sem Work Item vinculado são achado de processo, não detalhe.
- **Revisão automática já existente.** As threads costumam trazer o bot de code review IA. **Use como corroboração, nunca como substituto** — ele acha bug local e não enxerga governança, ADR nem escopo de release. Registre o que ele já pegou (evita duplicar) e, principalmente, **o que ele não tinha como pegar**.

## 2. Insumos complementares — use se houver, não pare se faltar

Combinado com a equipe: o dev deve anexar ao PR a **saída dos gates** e, quando houver, o **relatório de execução do Cursor**. Eles são **complemento, não pré-condição**.

**Procure a evidência de gate nesta ordem — pare na primeira que existir:**

1. **Pipeline / build validation do próprio PR.** Cheque antes de qualquer coisa (`azure-devops:pipelines_build` com `action: "get_status"` para um build conhecido, ou `action: "list"` filtrando por `branchName`, ou ainda o status/threads do PR). Já existe pipeline plugado nos PRs deste repo. Se houver build cobrindo a superfície do diff, **é essa a evidência** — a `110` diz explicitamente que o destino do gate é o CI, "não um pedido pontual do owner a cada rodada". Cobrar saída manual de terminal existindo pipeline verde é ruído.
2. **Saída anexada pelo dev**, se não houver pipeline que cubra.
3. **Pedido manual derivado** (§3) — só como fallback dos dois anteriores.

Antes de cobrar qualquer coisa, confira **o que o pipeline já cobre**: exigir do dev o que o CI já roda queima capital à toa, e o inverso (achar que o CI cobre o que ele não cobre) é pior. Se o pipeline roda parcialmente, cobre só o **delta**.

- **Se estiverem lá:** leia e trate exatamente como o `/revise` trata o relatório — ponto de partida, não fonte de verdade. Cruze contra o diff real. Desconfie especificamente da seção de desvios/"opcional" (ver §4).
- **Se faltarem:** **prossiga com a auditoria assim mesmo** e registre a ausência como item do veredicto. Nunca devolva "não dá para revisar sem os gates": a auditoria de aderência a rules, ADR e escopo não depende de suíte verde. Não fique esperando o dev. E não se limite a cobrar — **derive a lista exata de comandos deste PR** (§3, "Derivar do diff a lista exata de gates a exigir") e entregue-a pronta no comentário, para o pedido ser específico em vez de genérico.

## 3. Auditar contra a realidade, não contra a descrição

Liste os arquivos tocados com `azure-devops:repo_pull_request` (`action: "get"`, `includeChangedFiles: true`) — isso dá **a lista, não o diff**. O conteúdo real sai de duas fontes, nesta ordem:

1. **`git fetch` + `git diff <base>..<branch>` local** — mesmo caminho do `/audit-task`, é o que mostra o diff completo de verdade.
2. **`azure-devops:repo_file`** (`action: "get_content"`, `version: <branch>`, `versionType: "Branch"`) — arquivo a arquivo, quando não dá para ter a branch local.

Nunca audite pela lista de arquivos: ela diz *onde* mexeram, não *o que* fizeram. Diffs grandes estouram o limite e são salvos em arquivo — nesse caso **não delegue às cegas**: use `Grep` no arquivo salvo para achar os pontos quentes (termos do domínio da mudança) e `Read` com offset/limit nos trechos que importam. Leia o **código de verdade** dos arquivos centrais; resumo de diff não substitui.

**Delegue a leitura, nunca o julgamento.** Quando o diff é grande ou toca muitos arquivos, despache o subagente `scout` (`Agent`, `subagent_type: "scout"`) com duas coisas: o **alvo** (caminho do diff salvo, ou `base..branch`) e a **pergunta** — a rule, a ADR ou o critério que você quer confrontar. Ele devolve `arquivo:linha` + trecho literal e **não emite veredicto** — o veredicto continua seu. Um despacho por pergunta: *"confira X contra a rule `060`"* rende evidência utilizável; *"revise este PR"* rende resumo, e resumo é exatamente o que esta skill não aceita. O que volta são citações para você conferir, não conclusões para repassar.

### A lição que originou esta skill

**O título do PR não define o escopo da mudança — o diff define.** No PR #1003, "refatorar a página de login para usar controles de formulário" continha, embutida, a troca do protocolo de autenticação (Authorization Code + PKCE → ROPC/password grant) e a abertura de `directAccessGrantsEnabled` em clientes públicos do Keycloak. Ninguém lendo o título esperaria uma decisão de segurança lá dentro.

Portanto, **classifique a mudança pelo que ela faz, não pelo rótulo**. Pergunte sempre: *este diff muda protocolo, fronteira de módulo, modelo de domínio, superfície de autenticação/autorização, contrato de API, ou configuração de segurança?* Se sim, o rótulo "refatoração"/"ajuste"/"melhoria" é irrelevante — é mudança estrutural e cai na regra de ADR (`CLAUDE.md` §2).

Preste atenção especial a arquivos que costumam passar despercebidos num PR de UI: realms/config de identidade, `deploy/**`, `infra/**`, interceptors, guards, migrations.

### O gate é o das rules — abra-as, não confie na memória

A definição de pronto **não é replicada aqui**, porque cópia envelhece. A fonte é `.cursor/rules/110-cursor-workflow.mdc` §"Gate de pronto" e `.cursor/rules/060-dotnet-code-style-tests.mdc` §"Pronto ≠ `--filter`". **Abra os dois a cada rodada** quando o diff tocar backend.

Você não roda os gates do dev por ele — mas **pode e deve** rerodar o que for barato e discriminante quando houver dúvida real (rodar build/teste é verificação, não é escrever código de produto). Se não rodar, **declare explicitamente o que não rodou e por quê** (branch não está no working tree local, Docker indisponível, gate é de quem fecha). Silêncio não se distingue de esquecimento.

### Derivar do diff a lista exata de gates a exigir (fallback)

Só chegue aqui depois de esgotar o §2: **se o pipeline do PR já cobre a superfície do diff, não peça nada**. Este é o caminho de exceção, não o padrão — e ele tende a desaparecer conforme o CI assumir o gate.

Quando precisar pedir, **não peça "anexe os gates"**. O termo é jargão da casa e a leitura natural de um dev é rodar só o que ele mexeu — que é exatamente o que a `110` proíbe (`--filter` não é pronto; projeto fora da lista esconde vermelho). Pedido genérico produz print filtrado, e aí os dois lados acham que o combinado foi cumprido.

**Monte a lista de comandos deste PR e cole pronta no comentário.** Como derivar, sem criar cópia que envelhece:

1. Abra a `110` na seção de definição de pronto **da camada que o diff toca** (frontend ou backend) e leia **ali** os projetos com alvo de teste e os comandos da vez. Essa lista cresce quando nascem libs/apps — nunca a replique nesta skill, e releia a cada rodada antes de colar no PR.
2. Mapeie cada caminho do diff para o nome de projeto do workspace, resolvendo pelos `projects` de `platform/frontend/angular.json` (fonte dos nomes) cruzado com quem tem alvo de teste na `110`.
3. **Acrescente os consumidores.** A `110` é explícita: mexeu numa lib, quem a consome também entra no gate. Levante-os por busca real de import da lib/símbolo alterado no workspace — não por intuição.
4. `core` e `design-system` são os que mais escapam, porque quase todo diff passa de raspão por eles. Confira no diff se foram tocados de verdade antes de incluir ou omitir.
5. Peça a saída **em texto, não print**, e avise que suíte já vermelha sem relação com o diff é **achado a reportar, não ruído a normalizar**.

**Tom do pedido: comandos, não doutrina.** O dev não precisa internalizar a razão do gate para cumpri-lo — precisa saber o que rodar. Mande os comandos, uma linha dizendo por que **estes** projetos (ex.: "o diff encostou em `core` e `design-system`, não só na tela"), e a instrução de reportar vermelho pré-existente. **Corte** o histórico de incidentes, a explicação de por que `--filter` esconde vermelho e as citações de rule: isso é contexto de governança, fica com o usuário, e no comentário do dev vira sermão. Reconheça o atrito quando ele existir — pedir 8 comandos na mão é chato, e dizer que a intenção é virar script/pipeline compra colaboração em vez de resistência.

No backend, mesmo desenho — respeitando o **gatilho condicional** do `Integration.Tests` que está na própria `110`, em vez de mandar rodar a bateria inteira por hábito. Acertar a superfície é o rigor; bateria cega num diff de três arquivos só encarece a próxima iteração.

## 4. Rubrica

Aplique a rubrica de `docs/contexts/code-audit-mode.md` — não recrie outra. Em resumo: cobre o previsto? há escopo extra não aprovado? ADRs vigentes respeitadas? rules da área seguidas? testes adequados? há sincronização reversa spec ← código?

**"Rules da área" não é você adivinhando de memória:** abra `.cursor/rules/005-documentation-context-hierarchy.mdc`, deixe o mapa dela despachar pelas áreas que o diff toca, e **abra as rules que ela indicar**. O dev recebe metade delas automaticamente pelos `globs`; **para você não chega nenhuma**. Rule não aberta é rule não checada, e chutar produz resposta plausível — pior que nenhuma. O mesmo vale para os ADRs: liste `docs/adr/` e abra os que a área tocada envolve, em vez de confiar na linha-resumo do `CLAUDE.md` §8.

**Antes de chamar algo de violação de convenção, conte os irmãos.** Nome, sufixo ou padrão só é desvio se os pares **não** fizerem igual — e isso se mede abrindo os pares. Em 2026-08-14 acusei um método de prometer um lock inexistente; havia 11 irmãos com o mesmo sufixo e nenhum com lock, porque ali ele significa leitura rastreada. O achado errado virou correção e entrou no código.

Mais as perguntas que suíte verde não responde (critérios em `060` §"Desenho de teste — verde não é prova"):

- **A defesa dispara?** Se a entrega adiciona guard/fail-fast/limite/authz/header, provoque a condição e observe a consequência real — não aceite o teste como prova de si mesmo.
- **Algum teste novo é vácuo?**
- **O que foi chamado de "opcional" é mesmo opcional?** O que o autor precisou fazer para o próprio fix funcionar não é opcional; se o padrão existe em arquivos irmãos, o default é espelhar — o ônus é dele para argumentar por que os irmãos são seguros.

### Resíduo decidido não é achado

Antes de reportar, faça diff contra o registro canônico de resíduos (tabela "Resíduos e decisões" do build-log do passo, seção de status da ADR do lote) e contra o que já foi decidido em revisões anteriores deste mesmo PR. Resíduo com decisão registrada **não volta como achado** — só reabre com evidência nova, citada. Sem ela, a menção certa é "resíduo X segue como decidido".

## 5. Separe o objetivo do caminho

Quando o achado for de arquitetura, **não confunda "o que ele quis fazer" com "como ele fez"**. Quase sempre o objetivo do dev é legítimo e o problema está no caminho escolhido. A revisão fica muito mais útil (e muito menos desmoralizante) quando diz:

1. qual era o objetivo — reconhecido como válido;
2. por que **este caminho** custa caro, com impactos concretos e verificáveis;
3. **qual caminho alternativo atinge o mesmo objetivo** sem o custo.

Sem o item 3 a revisão vira veto. Com ele, vira direção.

## 6. Veredicto

Vocabulário de `code-audit-mode.md`: **conforme** / **conforme com ressalvas** / **não conforme**. Estruture: achado(s) bloqueante(s) → achados secundários → **pontos positivos** (nomeie o que foi bem feito; ser justo com o autor é parte do trabalho) → processo (ADR-0039, branch, task) → gates (o que rodou, o que não rodou e por quê).

Separe sempre **qualidade do código** de **conformidade de processo**. Um PR pode ter código exemplar e ainda ser "não conforme" por decidir, num PR, algo que cabia a um ADR — e dizer isso explicitamente evita que o dev leia o veredicto como crítica à competência dele.

## 7. Desfecho — o usuário decide

**Você propõe, o usuário decide**. Apresente o veredicto e ofereça as opções reais (reverter o trecho estrutural / formalizar via ADR / aceitar com ressalvas / adiar). Só depois do aval:

- **Comentar no PR** com `azure-devops:repo_pull_request_thread_write` (`action: "create"`, `content`, `status: "Active"`; para comentário ancorado em linha, `filePath` + `rightFileStartLine`), no formato do §6 — endereçado ao dev, em português, direto e sem hostilidade. Deixe explícito o que está bloqueado e o que ele pode tocar enquanto isso. Se os gates não vieram, inclua no comentário o **bloco de comandos derivado** (§3) em vez da cobrança genérica — e, na primeira vez com cada dev, apresente o termo "gate de pronto" apontando para a `110`, para o vocabulário se espalhar em vez de ser presumido.
- **Plano de correção**, se o usuário pedir: artefato em `.cursor/plans/<slug>-correcoes.plan.md`, nunca código. **Aplique a skill `plan-for-cursor`** antes de entregar — os passes de verificação e a seção que os registra.
- **Proposta de ADR**, se a mudança merecer uma e não tiver: não crie sozinho — aplique o critério de "quando oferecer ADR" da skill `domain-modeling` (difícil de reverter + surpreendente sem contexto + trade-off real) e proponha.
- **Registro na memória de sessão** quando a decisão ficar pendente, para a próxima sessão começar do saldo e não do zero.

Não vote no PR (aprovar/rejeitar) por iniciativa própria — o voto é do usuário, salvo pedido explícito.

## 8. Nunca edite o código do PR

Nem para achado pequeno ("só uma mensagem", "só uma string", "fix trivial") — regra do owner de 2026-07-09, sem exceção em pós-auditoria. Todo achado vira **item de lista para o dev ou para o Cursor executar**. O enforcement técnico em `.claude/settings.json` nega `Edit`/`Write` em `platform/**`, `services/**`, `infra/**`; não contorne via shell.
