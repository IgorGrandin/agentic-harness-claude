# agentic-harness-claude

Harness global do owner para o Claude Code: o `CLAUDE.md` global, 5 subagentes e
as skills de trabalho (inclusive os fluxos do BrixBroker). Substitui o
`agentic-harness-v4`, que fica congelado como backup do Codex e para rollback.

O plano de construção e as decisões estão em
[docs/plans/claude-harness.plan.md](docs/plans/claude-harness.plan.md).

## Conteúdo

| Caminho | Destino em `~/.claude/` | Função |
|---|---|---|
| `CLAUDE.md` | `CLAUDE.md` | Regras globais: evidência, permissões, memória e política de delegação |
| `agents/*.md` | `agents/` | Subagentes `scout`, `implementer`, `reviewer`, `verifier` e `architect_escalation` |
| `skills/<nome>/` | `skills/<nome>/` | Skills (a partir do S2) |

## Modelos

A sessão principal (root) roda em Sonnet 5.5 com effort medium e implementa a
maior parte do trabalho. Para slices difíceis, use `/effort high` ou `/model opus`.

| Agente | Modelo | Effort | Restrição |
|---|---|---|---|
| scout | `haiku` | low | Só leitura (`Read`, `Grep`, `Glob`, `Bash`) |
| implementer | `sonnet` | medium | Não abre subagentes; usado com `isolation: worktree` |
| reviewer | `opus` | high | Não edita |
| verifier | `sonnet` | medium | Não edita |
| architect_escalation | `opus` (depois `fable`) | high | Não edita; só decide |

Os modelos usam aliases, então acompanham a versão mais nova de cada família.
Não defina `CLAUDE_CODE_EFFORT_LEVEL` no ambiente: essa variável sobrepõe o
effort de cada agente.

## Instalar e reverter

O instalador (`scripts/install.ps1`) e o verify entram no S6. Até lá, nada deste
repositório é copiado para `~/.claude`.

O instalador vai gerenciar só o `CLAUDE.md`, os 5 agentes e as skills listadas.
Ele não toca `settings.json`, `projects/`, `sessions/`, `brixbroker/` nem
plugins. Antes de sobrescrever qualquer arquivo, faz backup em
`~/.claude/portable-backups/<timestamp>/`. Para reverter, basta restaurar esse
backup.
