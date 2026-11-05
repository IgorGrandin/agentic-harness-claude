# Plano: qualidade e custo do ciclo plan-task → execute-ig → revise

Status: **revisto em 2026-11-05**: o hook `PreCompact` (D3) foi removido porque o segundo auto-compact rodava 4–6 s depois do bloqueio (`~/.claude/handoffs/handoff.log`); D2 passa a 300k e o handoff do mod abre em 190k. O texto abaixo (E9, D2, D3, AC3–AC5) descreve o desenho original. Status anterior: **aprovado** em 2026-11-05, com D1–D5 como recomendado. S0–S3 integradas na branch `feature/execute-cycle-quality-cost` (S4); S5 e S6 são do owner. AC5 parcialmente verificado (o runner `claude plugin test` falha no Windows também no código intocado; as asserções novas rodaram e foram vistas vermelhas). Resíduos: `Composição:` dispara com qualquer menção a Integration/HostSmoke no corpo da fatia; `sid` do mod × `session_id` do hook fica para a S5.
Data: 2026-11-05.
Executor previsto: subagentes Sonnet 5.5 medium, uma fatia por subagente, cada um em worktree próprio. Integração, gates e commits ficam com a sessão principal.

## 1. Problema

Cada WI do BrixBroker passa por 3 ou 4 ciclos de `/execute-ig` e `/revise`, e o `/review-pr` ainda acha mais. O limite semanal do plano estoura uns 30 horas antes do reset, mesmo com Haiku.

### Evidência (levantada em 2026-11-05)

| # | Fato | Fonte |
|---|---|---|
| E1 | A sessão principal do `/execute-ig` roda com `claude-haiku-5-5` em quase todas as rodadas | `~/.claude/brixbroker/execute-rodadas.csv`, coluna `root_model` |
| E2 | Uma WI gera vários planos em cadeia; por exemplo, a 3691 tem `correcoes_plano_a` → `plano_b` → `b_testes_faltantes` (3 planos no CSV; o `plano_a` não está lá) | mesmo CSV, coluna `plan` |
| E3 | O `/execute-ig` com Haiku na sessão principal responde por 33,1% do custo registrado, e o prompt médio por turno fica perto de 395k tokens | `~/.claude/metrics/tokens-by-model.csv` (236 linhas), agregado por fase, papel e modelo |
| E4 | Das 91 sessões principais com Haiku, 81 têm prompt médio acima de 100k | mesmo CSV |
| E5 | O Haiku 5.5 cobra 5× mais acima de 100k de prompt: leitura de cache 0,05 contra 0,01, e saída 2,50 contra 0,50. O Sonnet 5.5 cobra 0,10 e 10,00 | tabela `$prices` em `~/.claude/scripts/log-tokens.ps1`, conferida em 2026-10-22 |
| E6 | O Opus em sessões avulsas e no `/plan-task` soma uns 32% do custo, com prompt médio de 230k a 280k | `tokens-by-model.csv` |
| E7 | O `settings.json` global só define `modelSettings.claude-sonnet-5-5.autoCompactWindow = 400000`. Não há chave no nível superior, e o Haiku compacta perto de 967k por padrão. A documentação aceita a chave no nível superior: "For every model: set `autoCompactWindow` in a settings file, such as `"autoCompactWindow": 200000` in `~/.claude/settings.json`" | `~/.claude/settings.json`; documentação `model-config.md` §"Set the auto-compact window" |
| E8 | O mod `handoff` oferece o Refresh em `OFFER_AT = 250_000`. O comentário no código supõe compactação entre 300k e 324k, o que não bate com E7. O mod também atende pedidos pelo arquivo `~/.claude/handoffs/.request-<sid>` | `benai-mods/plugins/handoff/hooks/register.tsx:8-10` e `:506-512` |
| E9 | Um hook `PreCompact` com matcher `auto` pode bloquear a compactação (exit 2 ou `"decision":"block"`). Se o bloqueio cair sobre um erro de limite de contexto que a API já devolveu, a requisição falha | documentação oficial `hooks.md` §PreCompact |
| E10 | A carga de contrato que o `/execute-ig` abre soma uns 141 KB: a skill (28 KB), `execute.md` (34 KB), `110` (24 KB), `CLAUDE.md` do Broker (15 KB), `analise.md` (11 KB), `060` (9 KB), TDD e code-review (7 KB cada) e `CLAUDE.local.md` (6 KB). Estimativa: 40k a 50k tokens antes da primeira fatia | `wc -c` nos arquivos. A conversão em tokens é **INFERÊNCIA**, não medida |
| E11 | Os critérios de aprovação de fatia (`execute-ig` §4) não proíbem commitar uma fatia com lacuna declarada nem exigem prova para as afirmações do corpo do commit | `skills/execute-ig/SKILL.md:130-145` |
| E12 | O plano de correção do `/revise` §4 só aplica o `plan-for-cursor`. A ancoragem em ADRs e rules (`plan-task` §3) não roda para esses planos | `skills/revise/SKILL.md:121-127` |
| E13 | O passe 4 do `plan-for-cursor` traça o caminho do fixture até a linha de produção, mas não confere se o harness de teste compõe o DI como o host real | `skills/plan-for-cursor/SKILL.md:60-108` |
| E14 | A invariante 1 do `/execute-ig` só deixa rodar os testes de Integration que a própria fatia cria ou altera. Os vizinhos da área tocada ficam para a pipeline 158 | `skills/execute-ig/SKILL.md:27`, `:162` |

Relatos de dois agentes, em sessões do BrixBroker, que confirmam E11 a E14:
- o plano contradizia um ADR;
- fatias foram commitadas "com lacuna declarada";
- o corpo do commit afirmava coisas que não tinham sido feitas;
- o harness de teste não usava a composição de produção;
- fixtures foram assumidos sem conferir;
- a revisão chegou tarde e em lote.

### Diagnóstico

São três causas que se somam:

1. **Contexto grande.** Turnos de cerca de 395k põem o Haiku na faixa de preço 5× mais cara (E3–E5). Além disso, a compactação perto de 967k (E7) resume as obrigações da skill, e elas se perdem.
2. **Regras sem trava.** As obrigações que o executor esquece não têm verificação mecânica (E11).
3. **Lacunas a montante.** O plano de correção não é conferido contra os ADRs (E12), os testes não usam a composição real (E13) e a integração só aparece tarde (E14). Cada revisão derivava cenários do zero, e cada passada achava coisas novas.

## 2. Decisões

| ID | Decisão | Recomendação | Alternativa |
|---|---|---|---|
| D1 | Modelo da sessão principal do `/execute-ig` nesta primeira fase | **Haiku 5.5**, com o novo regime (contexto curto e travas). O Sonnet entra no piloto (S6), pago pela economia medida | Sonnet já de início: custo 2 a 4× maior com o contexto de hoje (E5), o que estoura o limite antes de as fatias S1 a S3 reduzirem o contexto |
| D2 | Janela de compactação | `autoCompactWindow: 200000` no nível superior, e remover o override de 400k do Sonnet. Sem `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | 300k e 75%, como no artigo do Reddit: é uma impressão pessoal, sem medição |
| D3 | Compactação automática | Bloquear com `PreCompact` (matcher `auto`) e pedir o Refresh do mod `handoff`, **no máximo uma vez seguida por sessão** (fail-open: a segunda tentativa compacta). A compactação manual (`/compact`) continua livre | Deixar compactar |
| D4 | Ponto de handoff no `/execute-ig` | **Sempre** depois do commit de cada fatia com outras fatias pendentes: a sessão para e o dev abre uma sessão nova com `/execute-ig <WI>` | Só quando o contexto passar de X |
| D5 | Opus | Fica só no `/plan-task` e no `architect_escalation`. Sessões avulsas e de manutenção do harness passam para Sonnet. É hábito do owner; nenhum arquivo muda | Manter como está |

Todas as decisões são do owner. O executor não as reabre.

## 3. Fora do escopo

- Arquivos do repositório BrixBroker (`.cursor/commands/*.md`, `.cursor/rules/*`, `CLAUDE.md` do Broker). O que precisar mudar ali vira WI própria via `/spec-task`.
- Trocar o modelo do `reviewer`, do `scout` ou do `verifier`.
- Mudar o `/plan-task` além do que S4 prevê.
- Aplicar a mudança no `~/.claude/settings.json` real. O executor escreve o código e os testes do instalador; quem roda `scripts/install.ps1` é o owner, ou a sessão principal com autorização explícita dele.

## 4. Critérios de aceite

| AC | Critério observável |
|---|---|
| AC1 | `scripts/report-wi-cost.ps1` gera, por WI: custo em USD, número de sessões, prompt médio por turno separado por papel e modelo, e número de planos distintos em `execute-rodadas.csv` (padrão `wi_<id>_`). Linhas sem WI e WIs que só aparecem num dos CSVs entram como tal, sem erro |
| AC2 | `install.ps1` grava `autoCompactWindow: 200000` no nível superior do `settings.json` e remove `modelSettings.claude-sonnet-5-5.autoCompactWindow`. Se o objeto do modelo ficar vazio, remove o objeto; se `modelSettings` ficar vazio, remove `modelSettings`. Todas as outras chaves ficam semanticamente iguais (comparação profunda; o `ConvertTo-Json` reformata o arquivo, e isso é aceito) |
| AC3 | `install.ps1` instala `hooks/precompact-handoff.ps1` em `~/.claude/hooks/precompact-handoff.ps1` pela entrada `hooks` do `manifest.json`, e registra em `settings.json` um `PreCompact` com matcher `auto` que aponta para ele. Rodar duas vezes não duplica a entrada (identificada pelo nome do script, não pelo comando inteiro). Os hooks existentes (o `Stop` do `log-tokens.ps1` e qualquer `PreCompact` com outro matcher) ficam como estão |
| AC4 | O hook lê do stdin `session_id` e `trigger`. Com `trigger=auto`, `session_id` válido (`^[0-9A-Za-z-]{8,}$`) e **sem** o sentinela `~/.claude/handoffs/.precompact-blocked-<id>`: grava `.request-<id>` e o sentinela, imprime `{"decision":"block","reason":"..."}` e sai com 0. Com o sentinela presente: apaga o sentinela, não bloqueia (compactação segue) e registra a linha em `~/.claude/handoffs/handoff.log`. Com `trigger=manual`, JSON inválido ou `session_id` inválido: não grava nada, não bloqueia e sai com 0 |
| AC5 | O mod `handoff` oferece o Refresh em `OFFER_AT = 150_000`, com `SNOOZE = 40_000`, para que oferta mais adiamento fiquem abaixo da janela de 200k. O comentário do código passa a citar a janela de 200k |
| AC6 | No `/execute-ig`, depois do commit de uma fatia com outras pendentes, a sessão para, relata as fatias feitas e as pendentes e manda o dev abrir uma sessão nova com `/execute-ig <WI>` (D4). Uma sessão retomada carrega só o contrato da etapa em curso, pela tabela de carga da skill |
| AC7 | Uma fatia não é aprovada com lacuna declarada. A lacuna vira decisão do dev, registrada, ou teste obrigatório na própria fatia |
| AC8 | `check-slice-commit.ps1` roda **antes** do `git commit`, sobre a mensagem rascunho (`-MessageFile`), e de novo depois, como reconferência (`-Commit`). Dá exit 1 quando: falta algum dos três trailers; falta a seção `Afirmações:` (vale `Afirmações: nenhuma`); uma linha da seção não tem `prova:`; falta `[visto]` para o teste que o plano elegeu como discriminante da fatia; ou há marcador de lacuna fora das linhas isentas. Dá exit 2 se não conseguir ler a mensagem ou o plano. Commits sem `Execute-Slice` (os de correção do passo 6) ficam fora |
| AC9 | Fatia que toca persistência, DI ou host roda com `--filter` os testes de Integration existentes da classe ou do módulo tocado. Teste vizinho vermelho é rodado no run base num worktree temporário: vermelho lá também é pré-existente (registrar e seguir); verde lá é regressão da fatia. Sem Docker, registrar `UNVERIFIED` e seguir (a 158 cobre). Antes de cada fatia, o executor sonda os fixtures que ela usa e para se o plano se contradiz |
| AC10 | O passe 6 do `plan-for-cursor` passa a ser "ADRs e rules da área", e a linha `Rules` da tabela de verificações vira `ADR/Rules`, citando os ADRs e as decisões conferidas. Todo plano passa por esse passe, inclusive os de correção. O `check-plan.ps1` exige `ADR/Rules` (e a linha `Composição:` do AC11) só em plano novo ou alterado em relação ao `HEAD`. Plano já commitado e intocado continua aceito com a linha `Rules` antiga |
| AC11 | Cada fatia do plano que pede teste de Integration ou HostSmoke tem uma linha `Composição:` que nomeia o arquivo onde o host de produção registra os serviços do caminho testado e diz como o harness de teste usa esse mesmo registro, ou qual teste prova a composição |
| AC12 | O `/revise` §4 roda a ancoragem do `plan-task` §3 e o `check-plan.ps1` antes de entregar um plano de correção. O `/review-pr` roda o mesmo `check-plan.ps1` no plano de correção. Nos dois, só achado **bloqueante** (ou não bloqueante que o dev mandar corrigir) vira item de plano de correção. O resto vai para a tabela "Resíduos e decisões" do build-log, com a decisão registrada. As frases que hoje mandam o contrário são reescritas |
| AC13 | `scripts/verify.ps1 -RunTests` passa, `scripts/sync.ps1` gera as projeções de Codex e Antigravity sem drift, e os testes de presença (AC6, AC7, AC9, AC11, AC12) acham as frases-chave nas skills |

## 5. Matriz de cobertura

| AC | Comportamento | Fronteira | Teste ou check | Discriminante |
|---|---|---|---|---|
| AC1 | soma, separação e extração da WI | `scripts/report-wi-cost.ps1` | `tests/test-wi-cost.ps1` com fixtures: 2 WIs; 2 modelos; papéis `main` e `sub`; uma linha sem WI; um plano sem `wi_<id>_`; uma WI só num CSV | o total da WI A muda se a linha do outro modelo for ignorada; a contagem de planos da WI A é 2, não 3 (o plano sem WI não entra) |
| AC2 | merge da janela e poda | `scripts/install.ps1` | `tests/test-install.ps1`, caso novo, em `HOME` temporário, com `settings.json` no formato real (`hooks.Stop` em array, `modelSettings.claude-sonnet-5-5` com outra chave além da janela) | a outra chave do modelo continua lá; um modelo com só a janela some por inteiro |
| AC3 | instalação e registro idempotente | `scripts/install.ps1`, `manifest.json`, `scripts/verify.ps1` | `tests/test-install.ps1`: duas execuções seguidas; fixture com `PreCompact` de outro matcher | um único `PreCompact` com o nosso script; o `Stop` e o outro `PreCompact` preservados; o arquivo existe em `~/.claude/hooks/` |
| AC4 | bloqueio uma vez seguida, e fail-open | `hooks/precompact-handoff.ps1` | `tests/test-precompact-handoff.ps1`, em `HOME` temporário, com estes casos de stdin: `auto` primeira vez; `auto` com sentinela; `manual`; JSON inválido; `session_id` `..\x` | na primeira vez, stdout é JSON com `decision=block` e os dois arquivos existem; com sentinela, não sai `block`; com `..\x`, nenhum arquivo é criado fora de `handoffs/` |
| AC5 | limites da oferta | `benai-mods/plugins/handoff/hooks/register.tsx` | `register.test.tsx` existente, ajustado: sem oferta em 149.999; oferta em 150.000; depois de fechar, `snoozedTo` < 200.000 | o caso de 149.999 falha se `OFFER_AT` ficar menor; o caso de adiamento falha se `SNOOZE` passar de 49.999 |
| AC6 | parada por fatia e carga por etapa | `skills/execute-ig/SKILL.md` | `tests/test-obligations-execute-ig.ps1` (presença das frases-chave) e o piloto S6 | o teste falha se a frase da parada por fatia sumir |
| AC7 | nenhuma lacuna na aprovação | `skills/execute-ig/SKILL.md` §4 | o mesmo teste de presença, mais o AC8 | o mesmo |
| AC8 | trava do commit de fatia | `skills/execute-ig/scripts/check-slice-commit.ps1` | `tests/test-slice-commit.ps1`, um caso por condição: falta cada trailer (3 casos); falta `Afirmações:`; afirmação sem prova; falta `[visto]` do discriminante eleito; marcador fora de linha isenta; marcador dentro de `Decisão D2:` (exit 0); `Fatias pendentes:` com nomes (exit 0); plano sem discriminante eleito (não exige `[visto]`); plano inexistente (exit 2); commit sem `Execute-Slice` (ignorado, exit 0); corpo limpo (exit 0) | os casos "isentos" dão exit 0 e os de violação dão exit 1, pelo mesmo motor |
| AC9 | Integration da área e sondagem de fixtures | `skills/execute-ig/SKILL.md` §4 | teste de presença | o mesmo |
| AC10 | passe de ADRs e rules | `skills/plan-for-cursor/SKILL.md`, `skills/execute-ig/scripts/check-plan.ps1` | `tests/test-check-plan.ps1` com fixtures em `tests/fixtures/check-plan/`: plano novo sem `ADR/Rules` (exit 1); plano novo com a linha e de resto limpo (exit 0); plano commitado e intocado com `Rules` antiga (exit 0) | o caso positivo só passa se nada mais bloquear; o caso legado só passa se a regra respeitar o `HEAD` |
| AC11 | composição de produção | `skills/plan-for-cursor/SKILL.md` passe 4, `check-plan.ps1` | `tests/test-check-plan.ps1`: fatia nova com teste de Integration e sem `Composição:` (exit 1); com a linha (exit 0) | o mesmo motor nos dois sentidos |
| AC12 | ancoragem, check e convergência | `skills/revise/SKILL.md`, `skills/review-pr/SKILL.md` | `tests/test-obligations-plans.ps1` (presença; e ausência da frase antiga "Todo achado vira item da lista do plano de correção") | o teste falha se a frase antiga voltar |
| AC13 | contrato do repositório | todo o repositório | `scripts/verify.ps1 -RunTests` e `scripts/sync.ps1` | — |

Dimensões de risco:
- **Aplicam:**
  - idempotência e preservação do `settings.json` (AC2, AC3);
  - bloqueio sem fim: o mod `handoff` pode não consumir o pedido (mod desligado ou oculto, `claude -p`, subagente, `sid` diferente). O AC4 limita a uma vez seguida por sessão;
  - entrada hostil no hook: `session_id` com caminho (AC4);
  - falso positivo da trava de commit (AC8: linhas e seções isentas);
  - compatibilidade com os planos já commitados (AC10).
- **Não aplicam:** concorrência, transação, tenant e autorização. Não há estado compartilhado entre processos, só arquivos que um único dono escreve.

## 6. Fatias

As fatias S0 a S3 têm write-sets disjuntos e podem rodar em paralelo. S4 (integração) depende de todas. S5 e S6 são do owner.

### S0 — Linha de base de custo (AC1)
- **Write-set:** `scripts/report-wi-cost.ps1`, `tests/test-wi-cost.ps1`, `tests/fixtures/wi-cost/*`.
- **Entrada:** `~/.claude/metrics/tokens-by-model.csv` (separador `;`, aspas; colunas `session_id;updated_at;work_item;wi_source;phase;role;model;messages;input;cache_write_5m;cache_write_1h;cache_read;output;cost_usd`) e `~/.claude/brixbroker/execute-rodadas.csv` (coluna `plan`). Os caminhos entram como parâmetros, com esses valores como padrão.
- **Prompt médio:** `cache_read / messages`. Diga no cabeçalho da saída que é aproximado.
- **Saída:** tabela por WI no console, mais `-AsJson`.
- **Reuso:** a leitura de CSV segue o estilo de `skills/execute-ig/scripts/append-metrics.ps1`. Busque `Import-Csv` e `tokens-by-model` antes de criar outro helper.

### S1 — Compactação vira handoff (AC2–AC5)
- **Write-set:** `manifest.json`, `scripts/install.ps1`, `scripts/verify.ps1` (só a checagem da entrada `hooks` do manifesto contra a pasta `hooks/`), `hooks/precompact-handoff.ps1` (novo), `tests/test-install.ps1`, `tests/test-precompact-handoff.ps1` (novo), `benai-mods/plugins/handoff/hooks/register.tsx`, `benai-mods/plugins/handoff/hooks/register.test.tsx`.
- **Manifesto:** nova chave `"hooks": ["precompact-handoff"]`. O `install.ps1` copia cada item com `Install-File "hooks/<nome>.ps1"` (que instala em `~/.claude/hooks/`) e faz o merge no `settings.json` pelo padrão de `Merge-ModsSettings` (`scripts/install.ps1:77-99`): backup antes, `Assert-Inside`, UTF-8 sem BOM.
- **Formato do registro:** `"PreCompact": [{"matcher": "auto", "hooks": [{"type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"<home>/.claude/hooks/precompact-handoff.ps1\""}]}]`, no mesmo formato do `Stop` que já está no `settings.json`.
- **Hook:** qualquer exceção → exit 0 sem saída, porque o hook nunca pode travar a sessão.
- **⚠️ Conferir primeiro e reportar, sem inventar:**
  - se o `sid` do mod (`register.tsx:507`) é o mesmo `session_id` que o hook recebe (procure de onde vem `sid`). Se não for, o pedido não chega ao mod, e o fail-open do AC4 só evita o bloqueio sem fim. Reporte isso como um achado para a sessão principal;
  - se o `PreCompact` dispara em subagentes e no `claude -p`. Se não der para descobrir, registre como não verificado (o fail-open cobre o caso).
- **Testes do mod:** o `register.test.tsx` importa `claude-code/testing`, e nenhum documento diz como rodá-lo. Descubra o runner (procure em `benai-mods/` e no `package.json`, se houver). Se não achar, o AC5 sai como **não verificado** no relatório; não marque como verde.

### S2 — `/execute-ig`: handoff por fatia, carga por etapa e travas (AC6–AC9)
- **Write-set:** `skills/execute-ig/SKILL.md`, `skills/execute-ig/scripts/check-slice-commit.ps1` (novo), `tests/test-slice-commit.ps1` (novo), `tests/fixtures/slice-commit/*`, `tests/test-obligations-execute-ig.ps1` (novo).
- **Mudanças na skill:**
  1. **Parada por fatia (D4):** no §4, rodar `check-slice-commit.ps1 -MessageFile` sobre o rascunho **antes** do `git commit`; exit 1 → corrigir a mensagem ou a fatia antes de commitar. Depois do commit, rodar com `-Commit` como reconferência. Com fatias pendentes: relatar as feitas e as pendentes e encerrar mandando o dev abrir uma sessão nova com `/execute-ig <WI>`. A retomada já existe ("Run base", §0, e `resolve-plan.ps1`); não crie outro mecanismo. As métricas continuam como estão: os minutos de cada fatia ficam no corpo do commit, e o passo 9 agrega no fim da execução.
  2. **Tabela de carga por etapa,** no topo da skill: qual arquivo e qual seção cada etapa abre. Numa sessão retomada no §4, abrir só `execute.md` §2 e §Ciclo TDD, `execute-tdd.md` e, no plano, a seção da fatia pendente e as linhas dela na matriz.
  3. **Retomada:**
     - o preflight (§2) só roda de novo se o plano mudou desde o último commit de fatia (`git diff <último commit de fatia> -- <plano>` não vazio), e só sobre o delta;
     - a leitura das "Decisões do dev" na WI (§1) continua a cada retomada;
     - a pergunta de base fresca (§0) é feita uma vez por execução. Numa retomada, se o `origin/master` andou e os novos commits têm arquivos em comum com a branch ou com o plano, pergunte "seguir ou parar". Senão, registre WARN e siga.
  4. **Critério de aprovação novo:** "nenhuma lacuna declarada". Uma lacuna vira "Decisions during execution" (decisão do dev, registrada) ou teste obrigatório na fatia.
  5. **Corpo do commit com seção `Afirmações:`.** Toda frase factual sobre o comportamento entregue fica nessa seção, uma por linha, com `— prova: <teste|grep|comando>`. O que não tem prova sai do corpo. Sem afirmações, escreva `Afirmações: nenhuma`.
  6. **Antes de cada fatia:** sondar os fixtures e as tabelas que ela usa (leitura do código e uma execução focada), e parar se o plano se contradiz.
  7. **Integration da área:** fatia que toca persistência, DI ou host roda também os testes vizinhos, como diz o AC9. Reescreva a invariante 1 para deixar claro que isso é check focado, e que o projeto inteiro e o `run-gate.ps1` continuam proibidos.
- **Script `check-slice-commit.ps1`:**
  - recebe `-PlanPath` e, ou `-MessageFile`, ou `-Commit <sha>` (este lê `git log -1 --format=%B`);
  - **discriminante eleito:** linha do plano, dentro da seção da fatia (identificada pelo `Execute-Slice`), que casa com `discriminante da fatia:\s*` seguido de um nome de teste entre crases. É a frase literal que o `plan-for-cursor` passe 4(e) manda escrever. Sem essa linha, não exige `[visto]`. O `[visto]` tem de aparecer na mesma linha que o nome do teste eleito. Não reuse nem altere o `check-plan.ps1` (ele é da S3);
  - **marcadores de lacuna,** sem diferenciar maiúsculas: `lacuna`, `pendente`, `fica para`, `não implementad`, `TODO`, `known gap`, `deferred`, `follow-up`, `for later`, `out of scope`, `known limitation`;
  - **linhas isentas:** as que começam com `Decisão D<n>:` e as que estão dentro de uma seção `Fatias pendentes:`.
- **Teste de presença:** `tests/test-obligations-execute-ig.ps1` procura no `SKILL.md` as frases-chave dos itens 1, 4, 5, 6 e 7.

### S3 — Planos ancorados e revisões que convergem (AC10–AC12)
- **Write-set:** `skills/plan-for-cursor/SKILL.md`, `skills/execute-ig/scripts/check-plan.ps1`, `tests/test-check-plan.ps1`, `tests/fixtures/check-plan/*` (pasta nova; **não** edite `tests/fixtures/execute-resolver/*`, que é do `test-execute-resolver.ps1`), `skills/revise/SKILL.md`, `skills/review-pr/SKILL.md`, `tests/test-obligations-plans.ps1` (novo).
- **Mudanças:**
  1. **`plan-for-cursor`, passe 6 → "ADRs e rules da área":** além das rules pelo mapa da `005`, listar os ADRs vigentes da área e conferir que nenhuma fatia os contradiz. Conflito → `domain-modeling`, decisão do dev, como no `plan-task` §3. A linha `Rules` da tabela de verificações vira `ADR/Rules`, com os ADRs e as decisões citadas (por exemplo, "ADR-0060 D31: worker não compõe Crm"). Continuam sendo "doze passes"; atualize só o nome do passe 6 e as referências a ele.
  2. **Passe 4(h), composição de produção:** a linha `Composição:` do AC11, por fatia.
  3. **`check-plan.ps1`:** um plano é "novo" se não está no git (`git ls-files --error-unmatch` falha) ou tem diff contra o `HEAD`. Para plano novo: exige a linha `ADR/Rules` e exige `Composição:` em toda fatia que cita teste de Integration ou HostSmoke. Plano commitado e intocado: aceita a linha `Rules` antiga e não exige `Composição:`. A lista `$requiredRows` (`check-plan.ps1:28`) passa a depender disso.
  4. **`revise`:**
     - no §4, antes de entregar o plano de correção: rodar o `plan-task` §3 (ADRs, rules, release e vocabulário) para a área dos achados, aplicar o `plan-for-cursor` e rodar o `check-plan.ps1`;
     - reescrever a linha 127 ("Todo achado vira item da lista do plano de correção"): só achado bloqueante, ou não bloqueante que o dev mandar corrigir, vira item; o resto vai para a tabela "Resíduos e decisões" do build-log, com a decisão;
     - ajustar a linha 123 ("Desenhe um plano novo") e a linha 115 (que diz "passo 5") para apontar a tabela pelo nome.
  5. **`review-pr`:** na linha 132, o plano de correção (que já é só "se o usuário pedir") roda o `check-plan.ps1` e leva só os bloqueantes, ou os que o dev mandar corrigir. A regra "Resíduo decidido não é achado" (linha 107) continua.
- **Teste de presença:** `tests/test-obligations-plans.ps1` procura as frases novas e confirma que a frase antiga da linha 127 sumiu.

### S4 — Integração (AC13)
Feita pela sessão principal, não por um subagente.
- Integrar S0 a S3, nessa ordem, cada uma em seu próprio commit numa branch `feature/execute-cycle-quality-cost`.
- Rodar `scripts/sync.ps1`. Se ele precisar conhecer a pasta `hooks/` ou a chave nova do manifesto, ajuste-o aqui (o `sync.ps1` entra no write-set da S4). Depois rodar `scripts/verify.ps1 -RunTests`.
- Atualizar `README.md` (hook `PreCompact`, janela de 200k, parada por fatia) e o status deste plano.
- Mandar um `reviewer` revisar o diff integrado contra este plano, uma vez.
- Mandar o `verifier` rodar o gate (`verify.ps1 -RunTests` e `sync.ps1`) no commit exato.
- Listar como não verificados: o AC5, se o runner do mod não apareceu, e os ⚠️ da S1.

### S5 — Instalação (owner)
O owner autoriza e roda `scripts/install.ps1 -WhatIf`, e depois `scripts/install.ps1`. Conferências:
1. diff semântico do `~/.claude/settings.json` contra o backup;
2. numa sessão de teste, o `/compact` manual compacta normalmente;
3. numa sessão Haiku de teste, o `/context` mostra a carga inicial do `/execute-ig` (fecha a INFERÊNCIA E10) e a janela efetiva de 200k (fecha a premissa do D2);
4. na primeira vez em que a janela for atingida, o `~/.claude/handoffs/handoff.log` registra o pedido e o Refresh abre.

### S6 — Piloto e decisão sobre o Sonnet (owner)
1. Rodar `report-wi-cost.ps1` antes, como linha de base das WIs 3687, 3689, 3691 e 3701.
2. Duas WIs com o Haiku no novo regime → comparar custo por WI, sessões por WI, prompt médio, número de planos por WI e achados do `/revise` e do `/review-pr`.
3. Uma WI com o Sonnet medium na sessão principal do `/execute-ig`, no mesmo regime.
4. **Fica com o Sonnet se:** custo por WI ≤ 1,5× o do Haiku no novo regime **e** pelo menos um ciclo de correção a menos. Com uma WI por braço isso é um sinal, não uma prova: se o resultado ficar perto do limite, rode mais uma WI em cada braço antes de decidir. Se não bater, o Haiku continua, e as fatias S1 a S3 continuam valendo.

### Fora desta rodada, de propósito
- Adiantar a revisão (por exemplo, um `reviewer` por fatia). Aumenta o custo, e as travas da S2 atacam a mesma causa. Reavaliar depois do S6.
- Integração tardia em fatias que não tocam persistência, DI ou host. A 158 continua cobrindo.

## 7. Briefing dos subagentes (S0 a S3)

Cada subagente recebe:
- este arquivo;
- o ID da sua fatia;
- o write-set;
- os ACs;
- a regra: "não toque fora do write-set; não rode `install.ps1` contra o `HOME` real; não commite. Devolva o diff, os testes rodados com a saída literal e os pontos ⚠️ que não conseguiu fechar".

O modelo é Sonnet medium, com `isolation: worktree`.

## 8. Verificações feitas antes de entregar este plano

| Passe | O que verifiquei | Onde |
|---|---|---|
| Evidência | E1 a E14 lidas nos arquivos e CSVs citados | tabela §1 |
| Ambiente | as chaves de compactação e o comportamento do `PreCompact` lidos na documentação oficial (relato de subagente com citação literal). O nível superior de `autoCompactWindow` está citado em E7 | `model-config.md`, `hooks.md` |
| Encanamento | `Merge-ModsSettings` e `Install-File` existem; o mod atende `.request-<sid>` depois de `if (busy \|\| off) return`; `SNOOZE = 100_000` hoje; o `Stop` hook existe | `install.ps1:24-99`, `register.tsx:8-12` e `:504-512`, `settings.json` |
| ⚠️ Não verificado | `sid` do mod = `session_id` do hook; `PreCompact` em subagentes e no `-p`; runner do `register.test.tsx`; carga em tokens da E10 | S1, S4 e S5 conferem |
| Write-sets | S0 a S3 disjuntos. O `check-plan.ps1` e `tests/fixtures/check-plan/` só na S3; o `execute-ig/SKILL.md` e o `check-slice-commit.ps1` só na S2; o `manifest.json` e o `verify.ps1` só na S1; o `sync.ps1` só na S4 | §6 |
| Contradição | as frases das skills que contradiriam as regras novas estão nomeadas por linha para reescrita (`revise:115`, `:123`, `:127`; `review-pr:132`) | §6 S3 |
| Desafio | um `reviewer` desafiou a matriz em 2026-11-05: 6 achados bloqueantes (B1–B6) e 9 não bloqueantes (N1–N9). Todos foram incorporados nesta versão, menos dois deixados de propósito para depois do piloto ("Fora desta rodada") | este arquivo |
| Fora do escopo | nenhum arquivo do BrixBroker | §3 |
