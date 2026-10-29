# Codex e Antigravity (sync)

`scripts/sync.ps1` gera as configurações globais do Codex e do Antigravity a partir da fonte única deste repositório (`CLAUDE.md`, `agents/*.md`, `skills/**` e `core/roles/roles.json`), **sem nunca editar `skills/**`**.

O que é gerado:
- **Codex (`~/.codex/`):** `AGENTS.md`, `agents/*.toml` e `skills/<skill>/**` (incluindo `agents/openai.yaml` com `allow_implicit_invocation` derivado de `disable-model-invocation`). Preserva `~/.codex/skills/.system`.
- **Antigravity (`~/.gemini/`):** `GEMINI.md`, `config/agents/*.md` e `config/skills/<skill>/**`.

Aceita `-WhatIf`, `-Hosts codex|antigravity`, `-CodexHome`, `-GeminiHome` e `-PurgeLegacyHomes` (arquiva e remove `~/.agentic-harness`, `~/.agents`, `~/.codex/plans` e `~/.codex/memory-bank`). Faz backup de qualquer item substituído ou removido em `<home>/portable-backups/<timestamp>/`. Falha se `roles.json` divergir dos `agents/*.md` do Claude.

## Modelos e effort por papel

| Papel | Claude Code | Codex | Antigravity |
|---|---|---|---|
| root | modelo da sessão | modelo da sessão | modelo da sessão |
| scout | haiku low | gpt-6-luna low | Gemini 3.8 Flash low |
| implementer | haiku high | gpt-6-luna high | Gemini 3.8 Flash high |
| reviewer | sonnet medium | gpt-6.1-sol medium | Claude Sonnet 5.5 medium |
| verifier | haiku high | gpt-6-luna high | Gemini 3.8 Flash high |
| architect_escalation | opus medium | gpt-6.1-sol medium | Claude Opus 5.5 medium |

- Fable (Claude) e Astra (Codex) são proibidos no escalonamento; o Antigravity não tem equivalente.
- Antigravity não tem campo de effort: ele vira uma linha de instrução no corpo do agente (best effort). Os nomes de modelo no frontmatter são os do seletor e **ainda não foram validados** como valor do campo `model`.

## Adaptação das skills por host (`skillAdapters` em `core/roles/roles.json`)

As 21 skills em `skills/**` permanecem canônicas para o Claude Code. Ao projetá-las para Codex e Antigravity, o `sync.ps1`:

1. **Injeta o bloco `Host adaptation`** no topo do corpo de cada `SKILL.md` gerado, mapeando:
   - ferramentas (`Read`/`Edit`/`Write`/`Grep`/`Glob`/`Bash`/`AskUserQuestion`);
   - despacho de subagentes (`Agent` + `subagent_type` e `isolation: worktree`);
   - chamadas MCP do Azure DevOps (`azure-devops:<tool>`);
   - leitura obrigatória de `CLAUDE.md`, `CLAUDE.local.md` e `.claude/settings.json` do projeto como fontes de governança;
   - caminhos compartilhados de métricas e artefatos (`%USERPROFILE%\.claude\brixbroker\` e `%TEMP%\claude-handoffs\Broker\`), garantindo interoperabilidade entre os 3 hosts.
2. **Reescreve o caminho dos scripts compartilhados** de `.claude/skills/execute-ig` para `.codex/skills/execute-ig` (Codex) e `.gemini/config/skills/execute-ig` (Antigravity).
3. **No Codex:** converte chamadas `/<skill>` para `$<skill>` nas 21 skills do harness e gera `agents/openai.yaml`.
