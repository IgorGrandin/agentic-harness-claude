# Codex e Antigravity (sync)

`scripts/sync.ps1` gera `~/.codex/AGENTS.md` + `~/.codex/agents/*.toml` e `~/.gemini/GEMINI.md` + `~/.gemini/config/agents/*.md` a partir de `CLAUDE.md`, `agents/*.md` e `core/roles/roles.json` (modelo e effort por papel e host). Aceita `-WhatIf`, `-Hosts codex|antigravity`, `-CodexHome` e `-GeminiHome`; faz backup em `<home>/portable-backups/<timestamp>/` e remove agentes legados (com backup). Falha se `roles.json` divergir dos `agents/*.md` do Claude.

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
