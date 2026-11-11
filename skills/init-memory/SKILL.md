---
name: init-memory
description: Escopa a memória automática da pasta ao WI da branch atual — arquiva as notas de outros WIs, restaura as deste e cria a nota inicial se não houver. Use quando o usuário pedir "/init-memory", ao começar ou retomar um WI.
argument-hint: "número do WI (opcional — padrão: o número no nome da branch)"
disable-model-invocation: true
---

Prepara a memória do Claude Code desta pasta para **um WI só**, para notas de outros WIs não serem carregadas nem misturarem contexto. É exclusiva do Claude Code (a memória automática vive em `~/.claude/projects/<pasta>/memory`).

## O que fazer

1. Rode, na raiz do repositório de trabalho (acrescente `-WorkItem <número>` só se o usuário passou argumento):

   ```powershell
   & (Join-Path $env:USERPROFILE '.claude/skills/init-memory/scripts/wi-memory.ps1') -Action init
   ```

2. Se o script falhar por não achar o WI na branch, peça o número ao usuário e rode de novo com `-WorkItem`.
3. Mostre ao usuário a saída do script (o que foi arquivado, restaurado e criado) e **nada além disso**. Não edite nem apague nenhuma nota por conta própria.
4. Diga que a memória desta sessão já foi carregada **antes** da troca: para valer, o usuário deve rodar `/clear`. Se depois do `/clear` a sessão ainda souber de outro WI, abra uma sessão nova e avise, porque então o `/clear` não recarrega a memória.

## Regras do script (para você explicar, não para reimplementar)

- Nada é apagado. Notas de outros WIs vão para `memory/arquivo/` e saem do `MEMORY.md`; as deste WI voltam de lá.
- Nota pertence a um WI pela linha `wis: 3701, 3938` no frontmatter ou, nos arquivos `wi-*`, pelos números do nome. Nota sem WI (fato de ambiente) nunca é tocada.
- Nota que cita vários WIs fica ativa se o WI atual estiver entre eles.
- Para gravar uma nota nova que cita mais de um WI, inclua a linha `wis:` no frontmatter.
