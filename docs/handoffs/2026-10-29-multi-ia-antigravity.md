# Handoff: harness multi-IA (Claude, Codex, Antigravity)

Data: 2026-10-29. Origem: sessão do Claude Code neste repositório. Destino: Antigravity, no mesmo repositório.
Este arquivo fica em `docs/handoffs/` porque o Antigravity precisa abri-lo pelo workspace. A skill `/handoff` grava em `%TEMP%\claude-handoffs\Broker\`, pasta do BrixBroker.

## Objetivo

Gerar, a partir de uma fonte única neste repo, as configurações do Claude Code, do Codex e do Antigravity: regras, skills e agentes, com modelo e effort por agente em cada host.

O dono focou no Claude para testá-lo e agora quer ampliar para as outras IAs. Isso reabre a decisão T1 de [docs/plans/claude-harness.plan.md](../plans/claude-harness.plan.md) (2026-10-15). Atualize esse plano quando a reabertura for decidida.

## Estado (OBSERVED FACT)

- Nada foi alterado nesta sessão. Não gere arquivos antes das perguntas abaixo serem respondidas.
- O repositório já tem mudanças não commitadas do dono: `README.md`, `manifest.json`, `scripts/install.ps1`, `scripts/verify.ps1`, `tests/test-install.ps1` e a pasta `benai-mods/`. Não reverta nem commite sem pedido.
- **Claude Code:** agentes em `agents/*.md` com `model` e `effort` no frontmatter; 21 skills em `skills/`; regras em `CLAUDE.md` (cerca de 580 palavras). Instalador: `scripts/install.ps1`. Verificação: `scripts/verify.ps1 -RunTests`.
- **Codex:** `~/.codex/AGENTS.md` (cerca de 820 palavras). Agentes em `~/.codex/agents/*.toml` com `model` e `model_reasoning_effort`. Exemplos observados: `scout` com gpt-6-luna e effort low; `reviewer` com gpt-6-luna e effort high; `architect-escalation` com gpt-6.1-sol e effort medium. `implementer` e `verifier` não têm modelo definido no arquivo.
- **Antigravity:** `~/.gemini/GEMINI.md` (cerca de 2.200 palavras). Agentes em `~/.gemini/config/agents/*.md` com `model` no frontmatter. Valores observados: `architect_escalation` com `pro`; `scout`, `reviewer`, `implementer` e `verifier` com `flash`. Não há campo de effort nesses arquivos. As skills antigas ficam em `~/.gemini/config/skills/`.
- Os arquivos de Codex e Antigravity vêm da instalação v4 de outubro. Trate-os como legado a substituir, não como fonte.

## Feasibility (resposta ao dono)

- **Codex:** modelo e effort por agente são suportados no formato TOML (OBSERVED, nos arquivos existentes).
- **Antigravity, modelo:** o campo `model` existe no frontmatter (OBSERVED). Mas os valores observados são aliases de tier (`flash`, `pro`), não nomes como Opus ou Sonnet. Falta confirmar quais modelos o seletor do Antigravity oferece.
- **Antigravity, effort:** nenhum campo observado (OBSERVED: ausente). Suporte é HYPOTHESIS. Valide antes de prometer. Sem ele, o effort vira instrução no corpo do agente ou fica de fora.
- **Claude:** modelo e effort são nativos.

## Perguntas ao dono (fazer ANTES de escrever qualquer arquivo)

Faça uma por vez, cada uma com uma recomendação. Use `grilling` se estiver disponível.

1. **Antigravity, modelos:** qual modelo usar em cada papel? Confirme no seletor do Antigravity quais opções existem. Candidatos: Sonnet 5.5, Opus 5.5, Haiku 5.5, e os tiers `flash` e `pro` do legado.
2. **Antigravity, effort:** existe campo de effort ou de thinking por agente? Se não existir, o effort fica no corpo do agente ou é descartado?
3. **Codex, modelos e effort:** qual modelo e effort em cada papel? Candidatos observados: gpt-6-luna (low, medium, high) e gpt-6.1-sol (medium, high).
4. **Root (sessão principal):** qual modelo em cada host? Hoje o Claude usa Sonnet 5.5 em medium, com Opus para planejar.
5. **Fable:** o `CLAUDE.md` proíbe Fable no escalonamento. Essa proibição vale nos outros hosts também?
6. **Escopo:** Antigravity primeiro? Codex entra agora ou depois?
7. **Discrepância a resolver:** o plano (T5) diz implementer e verifier em sonnet/medium. Os `agents/*.md` e o `README.md` dizem haiku/high. Qual vale?

## Papéis atuais (fonte: `agents/*.md` e `README.md`)

| Papel | Claude (hoje) | Codex (legado) | Antigravity (legado) |
|---|---|---|---|
| root | Sonnet 5.5, medium; Opus para planejar | gpt-6.1-sol, low | a definir |
| scout | haiku, low | gpt-6-luna, low | flash |
| implementer | haiku, high | não definido | flash |
| reviewer | sonnet, medium | gpt-6-luna, high | flash |
| verifier | haiku, high | não definido | flash |
| architect_escalation | opus, high (xhigh só com pacote de insuficiência) | gpt-6.1-sol, medium | pro |

## Próxima ação concreta

Não escreva arquivos. Faça as perguntas 1 a 7 ao dono. Com as respostas:

1. Confirme no Antigravity os aliases de modelo e se há effort por agente. Teste com um agente de exemplo numa pasta temporária, fora do repo.
2. Crie `core/roles/roles.toml` com a tabela papel → modelo e effort, por host.
3. Crie `scripts/sync.ps1`. Ele deve gerar `GEMINI.md`, `~/.gemini/config/agents/*.md`, `~/.codex/AGENTS.md` e `~/.codex/agents/*.toml`. Deve ter `-WhatIf` e fazer backup em `portable-backups/`.
4. Verifique: `scripts/verify.ps1 -RunTests` fica verde; o diff gerado para `~/.claude` fica vazio; no Antigravity, uma tarefa pequena roda com cada modelo escolhido.

## Ponteiros

- [docs/plans/claude-harness.plan.md](../plans/claude-harness.plan.md): decisões T1 a T6 e A1 a A5. T1 será reaberta.
- [README.md](../../README.md): modelos atuais por agente e o que o instalador cobre.
- [CLAUDE.md](../../CLAUDE.md): as 7 regras de delegação, a serem portadas para `GEMINI.md` e `AGENTS.md`.
- `~/.agentic-harness/adapters/`: a tentativa multi-host de outubro (claude, codex, antigravity, cursor). Use como referência, não copie.
- `~/.agentic-harness/config/agents.toml`: limites de subagentes (máximo de 3 threads simultâneas).

## Skills sugeridas no Antigravity

- `grilling`: para fazer as perguntas 1 a 7 uma a uma, com recomendação.
- `repo-aware-architecture`: para desenhar `core/` e o gerador.
- `takeover`: para retomar este documento no início da janela.

## Sensível

Nenhuma credencial foi registrada aqui. Não copie `~/.codex/auth.json`, tokens nem hostnames de controle remoto para o repo.
