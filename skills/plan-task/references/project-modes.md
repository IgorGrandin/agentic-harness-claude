# Modos do projeto: BrixBroker × local

`/spec-task`, `/plan-task` e `/execute-ig` nasceram para o BrixBroker. Este arquivo é a fonte única de como eles rodam em qualquer outro repositório (GranHarmony, GranBrain, etc.) sem exigir `CLAUDE.md`, `CLAUDE.local.md`, Azure Boards nem `.cursor/commands/`.

## Detecção (primeiro passo de cada skill)

| Modo | Sinal | Efeito |
|---|---|---|
| **BrixBroker** | existe `.cursor/commands/execute.md` na raiz do repositório | a skill vale como escrita, sem mudança |
| **Local** | qualquer outro repositório git | as substituições abaixo valem no lugar do que é só do BrixBroker |

Fora de um repositório git, pare e diga qual pasta o dev deve abrir (por exemplo, um cofre do Obsidian não é o repositório do projeto). Nunca force o modo BrixBroker num repositório que não tem `.cursor/commands/execute.md`.

## Fontes do modo local

Leia, nesta ordem, o que existir: `backlog/WORKFLOW.md`, `AGENTS.md`, `CLAUDE.md`, `docs/memory-bank/INDEX.md`. São **contexto e contrato de processo do projeto**; nenhum deles é pré-condição para a skill rodar. Quando `backlog/WORKFLOW.md` existe, ele define IDs, estados, aprovação, relatórios e gate, e vence esta tabela em divergência. Sem ele, valem os padrões abaixo.

- **IDs:** string numérica com pelo menos quatro dígitos (`0005`). Casar por prefixo exato, nunca por data de modificação.
- **Task (fonte canônica):** `backlog/tasks/<id>-<slug>.md`, com `Decisões do dev` (`D1`, `D2`…) e critérios `AC1`, `AC2`…. Não há Work Item nem espelho remoto.
- **Plano:** `backlog/plans/<id>-<slug>.plan.md` quando `backlog/plans/` existe; senão `.cursor/plans/wi_<id>_<slug>.plan.md`. O diretório existente do repositório vence.
- **Branch de trabalho:** a que o `WORKFLOW.md` manda; sem ela, `feature/<id>-<slug>` a partir da padrão. A branch padrão não recebe commit direto.
- **Relatórios e gate:** fora do checkout, em `%TEMP%/<nome-do-repo>-execution/<id>/<sha>/<run-id>/` (`report.md`, `gate.json`), no formato do `WORKFLOW.md` quando houver. Os comandos do gate vêm do `AGENTS.md` (ou `CLAUDE.md`) conforme a superfície alterada.

## Substituições por skill

### `/spec-task`

- Sem Azure: pule a criação do Work Item (§4.1) e a consulta WIQL (§3). O ID é o próximo livre em `backlog/tasks/`, conferido logo antes de gravar. Para a checagem de conflito, leia as tasks locais com `status: in_progress`, os planos relacionados e os diffs de branches identificáveis; registre que isso não prova ausência de trabalho concorrente.
- O arquivo em `backlog/tasks/` é a única fonte. O texto não é "pronto para colar no Azure Boards".
- Referências de arquitetura vêm das fontes do modo local, não de ADRs ou rules do BrixBroker.

### `/plan-task`

- **§1 e §2:** leia a task local; não consulte Azure. Divergência entre task e código é pergunta ao dev, como no §4 da skill.
- **§3:** ancore nas fontes do modo local. Não imponha ADRs, rules, scripts ou projetos de outro repositório.
- **§5:** o corpo do plano segue o `WORKFLOW.md` ("Plano e qualidade") quando existir, senão a ordem da skill. O frontmatter usa `task: "<id>"` e `approval: pending|approved` quando o repositório pede; o `plan-for-cursor` continua sendo a régua. "Cursor" no nome da skill não restringe o executor.
- **§6:** as decisões gravam só na task local (não há Work Item). Nada de push ou PR sem pedido.

### `/execute-ig`

- **Autoridade:** a invocação de `/execute-ig <id|plano>` autoriza implementar **somente** o plano selecionado, aprovado e commitado. Não depende de `CLAUDE.md` nem de `CLAUDE.local.md`, e não autoriza push, PR, publicação ou deploy. Regras de permissão `deny` do dev continuam valendo.
- **Pulam:** `.cursor/commands/execute*.md` e a rule `110`/`060` (não existem), `check-owner-blockers.ps1` e a lista do owner (passos 5, 7 e 10), a delegação à pipeline 158, `resolve-artifact-paths.ps1`, `render-evidence-block.ps1` (precisa do manifesto do `run-gate.ps1`), as métricas do passo 9 e o `az rest`.
- **Valem sem mudança:** passo 0 (a base de frescura é a branch padrão do remoto, não `origin/master` fixo), resolução do plano com `-PlanDirectory` apontando para o diretório do plano, um commit por fatia com `check-slice-commit.ps1` e os trailers `Execute-*`, revisão independente do diff integrado, gate uma vez contra o último commit em árvore limpa, parada após cada fatia pendente.
- **Preflight, revisão e gate:** os critérios vêm do `WORKFLOW.md` ("Execução e evidência") e do `AGENTS.md`; o `reviewer` recebe esses documentos no lugar de `execute-code-review.md`. O `verifier` roda os comandos do gate contra o SHA e grava `gate.json`.
- **Decisões do dev:** leia a seção na task local em toda sessão; ela é a fonte, o plano é cópia.
- **Subagentes:** a regra "só sessão principal" é do BrixBroker. No modo local, prefira um único writer; `implementer` só com write-sets disjuntos, como o `WORKFLOW.md` e o `AGENTS.md` mandarem.
- **`show-slice.ps1`:** se não reconhecer o formato do plano, leia só a seção da fatia pendente e as linhas da matriz que a citam.
