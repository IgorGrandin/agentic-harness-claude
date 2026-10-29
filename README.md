# agentic-harness-claude

Harness global pessoal do dev para o Claude Code: o `CLAUDE.md` global, 5 subagentes e
as skills de trabalho (inclusive os fluxos do BrixBroker). Substitui o
`agentic-harness-v4`, que fica congelado como backup do Codex e para rollback.

O plano de construção e as decisões estão em
[docs/plans/claude-harness.plan.md](docs/plans/claude-harness.plan.md).

## Conteúdo

| Caminho | Destino em `~/.claude/` | Função |
|---|---|---|
| `CLAUDE.md` | `CLAUDE.md` | Regras globais: evidência, permissões, memória e política de delegação |
| `agents/*.md` | `agents/` | Subagentes `scout`, `implementer`, `reviewer`, `verifier` e `architect_escalation` |
| `skills/<nome>/` | `skills/<nome>/` | As 21 skills listadas em `manifest.json` |
| `benai-mods/` | `plugins/marketplaces/benai-mods/` e chaves em `settings.json` | Os 9 mods do Claude Code como marketplace `benai-mods`, habilitados globalmente |
| `manifest.json` | — | Lista explícita do que o instalador gerencia |

## Modelos

A sessão principal (root) roda em Sonnet 5.5 com effort medium e implementa a
maior parte do trabalho. Para planejar (`/plan-task`, `/plan-for-cursor`,
`/change-task`) e para slices difíceis, troque a root com `/model opus`; o Opus
também fica no `architect_escalation`.

| Agente | Modelo | Effort | Restrição |
|---|---|---|---|
| scout | `haiku` | low | Só leitura (`Read`, `Grep`, `Glob`, `Bash`) |
| implementer | `haiku` | high | Não abre subagentes; usado com `isolation: worktree` |
| reviewer | `sonnet` | medium | Não edita |
| verifier | `haiku` | high | Não edita |
| architect_escalation | `opus` (teto: Opus; nunca Fable) | high, depois xhigh | Não edita; só decide |

Os modelos usam aliases, então acompanham a versão mais nova de cada família.
Não defina `CLAUDE_CODE_EFFORT_LEVEL` no ambiente: essa variável sobrepõe o
effort de cada agente.

## Instalar e reverter

Antes de instalar, valide o repositório:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1 -RunTests
```

Para ver o que mudaria sem alterar nada:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install.ps1 -WhatIf
```

Para instalar:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install.ps1
```

O instalador gerencia só o que o `manifest.json` lista: o `CLAUDE.md`, os 5
agentes, as skills e o marketplace de mods. Cada skill é substituída por inteiro, então arquivos
deixados por um harness anterior não sobrevivem. Do `settings.json` ele muda só as chaves `extraKnownMarketplaces.benai-mods` e `enabledPlugins` dos mods; o resto do arquivo fica como está. Ele não toca
`projects/`, `sessions/`, `brixbroker/`, outros plugins nem skills fora da lista.

Depois de instalar, reinicie o Claude Code e confira os mods com `/plugin`.

Antes de substituir qualquer item, faz backup em
`~/.claude/portable-backups/<timestamp>/`. Para reverter, copie o conteúdo
desse backup de volta para `~/.claude/` e reinicie o Claude Code.

## Validação

O `scripts/verify.ps1` confere o contrato do repositório:
- **manifesto:** bate com as pastas;
- **AC1:** nenhuma mecânica do Codex nas instruções;
- **AC2:** as skills de fluxo continuam de invocação manual;
- **AC4:** modelo, effort e restrições de cada agente; Fable proibido;
- **AC5:** o `CLAUDE.md` tem no máximo 600 palavras e as 7 regras de delegação;
- **AC7:** o contrato de cobertura tem uma fonte só;
- **links:** nenhum link quebrado.

Com `-RunTests`, roda também os testes de `tests/`:
- os resolvers e as métricas do `/execute-ig`;
- o instalador, num `~/.claude` temporário.
