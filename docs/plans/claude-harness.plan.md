# Plano: harness global nativo do Claude Code (recomeço)

Status: **aprovado** em 2026-10-15 (A1, A3, A4 e A5 conforme recomendado). S1 em andamento.
Substitui: `claude-native-adapter.plan.md` (refino multi-host, abandonado).
Data: 2026-10-15.

## Objetivo

Criar um harness global novo, só para o Claude Code. Ele reaproveita o
conteúdo das skills e os scripts testados do v4 e descarta a camada multi-host
(kernel, runner, adapters, wrappers do Codex). O `agentic-harness-v4` fica
congelado: não é apagado e serve de backup e rollback.

## Decisões já tomadas

| # | Decisão | Fonte |
|---|---|---|
| T1 | O Claude Code passa a ser o agente principal; o Codex deixa de receber manutenção | owner, 2026-10-15 |
| T2 | O v4 é congelado, não apagado. As instalações do Codex (`~/.codex`, `~/.agents`, `~/.agentic-harness`) não são tocadas | owner + este plano |
| T3 | As skills do BrixBroker ficam fora do repo do produto, em `~/.claude/skills/`, exclusivas do owner | ADR-0039 do BrixBroker (`docs/adr/0039-...md:64-66`) |
| T4 | Root: Sonnet 5.5 em effort medium; Opus ou effort high em slices difíceis | owner, 2026-10-15 |
| T5 | Roles: scout `haiku`/low; implementer `sonnet`/medium; reviewer `opus`/high; verifier `sonnet`/medium; architect `opus`/high → `opus`/xhigh (Opus é o teto; Fable proibido) | recomendação Anthropic + owner, 2026-10-15 |
| T6 | Os nomes das skills não mudam (`/plan-task`, `/revise`...), porque o ADR-0039 e os hábitos do owner os citam | ADR-0039 |

## Decisões abertas (com recomendação)

| ID | Decisão | Recomendação | Alternativa |
|---|---|---|---|
| A1 | Distribuição | Repo git + script que sincroniza para `~/.claude/` (sem prefixo; inclui o `CLAUDE.md`) | Plugin: as skills ganham prefixo (`/brix:plan-task`) e o plugin não carrega `CLAUDE.md`. Só compensa para distribuir a outras pessoas, o que o ADR-0039 exclui |
| A2 | Nome e local do repo | **Decidido pelo owner:** `Documents/Projects/agentic-harness-claude`, projeto separado | — |
| A5 | Destino das instalações do Codex (`~/.codex`, `~/.agents`, `~/.agentic-harness`) | Arquivar em zip e não apagar. `~/.agents/skills` tem skills que não vieram do v4 (automate, canvas, create-hook...) | Apagar depois de confirmar que o Codex não será mais usado |
| A3 | Revisão no `/execute` | A root verifica cada slice no próprio loop; uma passada do reviewer Opus high no diff integrado; o verifier roda o gate final no commit | Reviewer e verifier por slice, como no v4 (custo maior; a Anthropic desaconselha subagentes para verificação pequena) |
| A4 | Hooks na v1 | Nenhum; reavaliar depois do primeiro mês de uso | Hook de Stop ou de PreToolUse para o gate em árvore limpa |

## Política de delegação (fonte única: o `CLAUDE.md` global)

As skills dizem **o que** precisa ser independente. O `CLAUDE.md` diz **quem** faz.

- A root implementa e roda os checks focados no próprio loop.
- O **scout** faz leitura e busca em volume (inclusive o antigo `diff-evidence`) e devolve só a evidência literal. O julgamento fica com quem chamou.
- O **reviewer** entra uma vez por entrega, com contexto limpo, sobre o diff integrado e o plano. Reporta só achados que afetam correção ou requisitos.
- O **verifier** roda o gate final contra o commit exato e devolve a evidência, sem consertar nada.
- O **implementer** só é usado em slices paralelos com write-sets disjuntos, cada um com `isolation: worktree`.
- O **architect_escalation** é chamado para decisão de arquitetura ou de spec que a root não consegue resolver com evidência. Sobe para effort xhigh, ainda em Opus, só com um pacote de insuficiência; Fable nunca é usado.
- Não usar subagente para o que cabe em poucas chamadas de ferramenta.

## Estrutura alvo

```
agentic-harness-claude/
  README.md                 # o que é, instalar, rollback
  CLAUDE.md                 # global, ≤ 600 palavras
  agents/                   # scout, implementer, reviewer, verifier, architect_escalation
  skills/<nome>/            # 17 skills (tabela abaixo)
  scripts/install.ps1       # sincroniza com backup; -WhatIf
  scripts/verify.ps1        # contrato do repo
  tests/                    # testes dos scripts do execute + do instalador
```

Conteúdo do `CLAUDE.md` global: precedência das instruções do projeto; rótulos
de evidência; níveis de permissão; regras de memória; a política de delegação
acima; o ciclo de sessão em 3 linhas. Kernel, runner, perfis e mecânica do
Codex saem.

## Migração das skills

| Skill | Fonte no v4 | Trabalho |
|---|---|---|
| grilling, brainstorming, takeover | `source-claude/ORIGINAL.md` | Copiar |
| handoff | `source-claude/ORIGINAL.md` | Copiar; conferir o caminho `claude-handoffs\Broker` |
| domain-modeling | `SKILL.md` + formatos | Copiar |
| systematic-debugging, repo-aware-architecture | `SKILL.md` + `references/` | Tirar a seção "single-kernel worker" |
| sdd-workflow | `SKILL.md` | Reescrever curto, sem worker (fast lane e lane completa) |
| plan-for-cursor | `ORIGINAL.md` + bullets do wrapper Codex | Original + `references/coverage-contract.md` (matriz AC, grafo de slices, desafio do reviewer, evidência red); é o dono do contrato |
| plan-task | `ORIGINAL.md` + bullets do wrapper | Original + referência ao contrato do plan-for-cursor |
| spec-task | `ORIGINAL.md` | Copiar |
| change-task | `SKILL.md` (nascida no Codex) | Trocar `$x` → `/x` e referenciar o contrato |
| revise | `ORIGINAL.md` + modos do wrapper | Original + modos pre-gate/post-gate + fallback sem relatório; `diff-evidence` → `scout` |
| audit-task, review-pr | `ORIGINAL.md` / `SKILL.md` | `diff-evidence` → `scout` |
| revise-and-deploy | `SKILL.md` + `references/` | Copiar; conferir a delegação |
| execute | `source-brixbroker/execute.md` + `SKILL.md` do v4 + scripts | Reescrever nativo: a ordem do v4 (resolver → matriz → slices → `/revise pre-gate` → commit em árvore limpa → gate no SHA → `/revise post-gate` → métricas), A3 para revisão, raiz da skill `~/.claude/skills/execute`, métricas em `~/.claude/brixbroker/` |

Ficam de fora: `bin/agentic-*.ps1`, `core/`, `profiles/`, `adapters/`,
`global/`, `config/`, `scripts/materialize.ps1`, `scripts/migration-tools.ps1`
e todos os `agents/openai.yaml`.

## Slices

| # | Slice | Escreve | ACs | Depende de |
|---|---|---|---|---|
| S1 | Repo, `CLAUDE.md` e agentes | `README.md`, `CLAUDE.md`, `agents/*` | AC4, AC5 | A1, A2 |
| S2 | Skills genéricas | grilling, brainstorming, takeover, handoff, domain-modeling, systematic-debugging, repo-aware-architecture, sdd-workflow | AC1, AC2 | S1 |
| S3 | Skills de planejamento | plan-for-cursor (+ contrato), plan-task, spec-task, change-task | AC1, AC2, AC7 | S1 |
| S4 | Skills de auditoria | revise, audit-task, review-pr, revise-and-deploy | AC1, AC2 | S3 (contrato) |
| S5 | `/execute` | `skills/execute/**`, testes dos scripts | AC1, AC6 | S3, S4, A3 |
| S6 | Instalador e verify | `scripts/*`, `tests/test-install.ps1` | AC3, AC8 | S1–S5 |
| S7 | Rollout (autorização separada) | Backup completo de `~/.claude/{CLAUDE.md,agents,skills}` → remover os 17 diretórios de skill, os 5 agentes e o `CLAUDE.md` instalados pelo v4 → instalar pelo `agentic-harness-claude` → nota de congelamento no README do v4 | AC9 | S6 |

S2 e S3 podem andar em paralelo. As demais são sequenciais.

O instalador só gerencia `CLAUDE.md`, os 5 agentes e as 17 skills. Ele nunca
toca `settings.json` (que tem os seus hooks em `localhost:3001`), `projects/`,
`sessions/`, `brixbroker/` nem plugins. Antes de sobrescrever, faz backup em
`~/.claude/portable-backups/<timestamp>/`.

## Matriz de cobertura

| AC | Comportamento observável | Check | Discriminante |
|---|---|---|---|
| AC1 | Nenhuma skill instalada fala de Codex | Grep em `<alvo>/skills/**/*.md` por `Codex`, `$<skill>`, `.codex`, `.agents`, `openai.yaml`, `Luna`, `Sol` | Hoje encontra "Codex interface" em `plan-task` |
| AC2 | Frontmatter original preservado | `disable-model-invocation` e `argument-hint` de cada `ORIGINAL.md` presentes no `SKILL.md` | Hoje faltam no `plan-task` instalado |
| AC3 | Instalação segura | Install em diretório temporário: backup criado; arquivos fora da lista gerenciada intactos (hash de `settings.json` antes e depois igual) | Um `settings.json` sentinela alterado faz o teste falhar |
| AC4 | Agentes conforme T5 | Parse do frontmatter: modelo, effort, `disallowedTools` em reviewer, verifier e architect | Reviewer sem `disallowedTools` falha |
| AC5 | `CLAUDE.md` enxuto e com a política de delegação | ≤ 600 palavras; contém as 7 regras de delegação; sem `kernel`, `runner` nem `Codex` | Hoje: cerca de 2.000 palavras |
| AC6 | `/execute` preserva a ordem e a mecânica do Claude | Asserções de texto: gate depois do commit; worktree só para paralelos; métricas em `.claude\brixbroker`; testes do resolver verdes | Ordem invertida ou caminho `.codex` falha |
| AC7 | O contrato de cobertura tem uma fonte só | Um bullet-âncora do contrato aparece em exatamente 1 arquivo | Duplicação acha 2 ou mais |
| AC8 | Pipeline do repo verde | `scripts/verify.ps1` e `tests/*.ps1` | — |
| AC9 | Funciona de verdade no BrixBroker | Smoke em sessão nova: `/handoff` + `/takeover`; `/plan-for-cursor` sobre um plano existente, só leitura; `/revise` sobre uma entrega já auditada | — |

Riscos fora do escopo: concorrência, transação e tenant não se aplicam
(scripts e Markdown). O risco real é a integridade de `~/.claude`, coberto por
AC3 e pelo backup.

## Riscos

- **Perder melhorias do v4 ao partir dos originais:** mitigado pelo contrato de cobertura (S3) e pela lista explícita de deltas do revise e do execute.
- **Skills instaladas hoje pelo v4 serão sobrescritas:** existe backup, e o rollback é restaurar a pasta.
- **O Cursor continua executando planos:** `plan-for-cursor` mantém o formato `.cursor/plans`; nada muda para o Cursor.

## Próximo passo

Responder A1–A4. Com isso a implementação segue S1 → S6. O S7 (instalar em
`~/.claude`) só roda com a sua autorização.
