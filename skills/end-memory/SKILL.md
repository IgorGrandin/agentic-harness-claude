---
name: end-memory
description: Encerra a memória do WI da branch atual — move todas as notas desse WI para memory/arquivo e as tira do índice, sem apagar nada. Use quando o usuário pedir "/end-memory", ao fechar ou mergear um WI.
argument-hint: "número do WI (opcional — padrão: o número no nome da branch)"
disable-model-invocation: true
---

Encerra a memória de **um WI** nesta pasta: as notas dele saem do índice carregado a cada sessão e vão para `memory/arquivo/`. É exclusiva do Claude Code. Pode ser desfeita com `/init-memory` naquele WI.

## O que fazer

1. Rode, na raiz do repositório de trabalho (acrescente `-WorkItem <número>` só se o usuário passou argumento):

   ```powershell
   & (Join-Path $env:USERPROFILE '.claude/skills/init-memory/scripts/wi-memory.ps1') -Action end
   ```

2. Se o script falhar por não achar o WI na branch, peça o número ao usuário e rode de novo com `-WorkItem`.
3. Mostre ao usuário a saída (o que foi arquivado). Atenção a linhas "cita também WI x": a nota fala de outro WI ainda ativo. Pergunte se ele quer restaurá-la com `/init-memory <outro WI>`.
4. Não edite nem apague notas. Diga que a mudança vale a partir do `/clear` ou de uma sessão nova, porque a sessão atual já carregou a memória.
