---
name: handoff
description: Compacta a sessão atual num documento de handoff para uma janela nova retomar exatamente daqui. Use quando o usuário pedir "/handoff" ou "fazer handoff", antes de fechar a sessão ou perto do limite de contexto.
argument-hint: "Em que a próxima sessão vai focar (opcional)"
disable-model-invocation: true
---

Escreva um documento de handoff resumindo a conversa atual para que um agente novo, numa janela nova, continue o trabalho exatamente de onde parou.

Salve em `%TEMP%\claude-handoffs\Broker\<YYYY-MM-DD-HHmm>-<slug>.md` — fora do workspace, porque é estado de trabalho efêmero, não artefato de spec: não entra na hierarquia do `CLAUDE.md` §3 e o Cursor não o lê. O slug é um kebab-case curto do foco da sessão (ex.: `adr-0033-step3-d3-correction`).

Inclua:

- Onde a sessão parou e qual é a próxima ação concreta — uma ação clara, não uma lista de opções a explorar.
- Decisões pendentes do owner e bloqueios (ex.: "aguardando o Cursor executar C1-C3", "aguardando o owner decidir X").
- Ponteiros para release/ADR/scope/plano do Cursor em foco, e para as entradas de `MEMORY.md` relevantes — cite pelo caminho ou nome, não copie o conteúdo.
- Uma seção **Skills sugeridas** com o que o próximo agente deve invocar ao retomar (ex.: `mem-search` para reconstituir uma memória citada, `/takeover` para ler este documento).

Não duplique o que já está capturado em outros artefatos (specs, ADRs, planos do Cursor, `MEMORY.md`, commits, diffs) — referencie por caminho em vez de copiar.

Redija qualquer informação sensível (chaves, senhas, dados pessoais).

Se o usuário passou argumento, trate como o foco da próxima sessão e adapte o documento a isso.

Mantenha o documento curto — o objetivo é ser barato de ler no início da próxima janela, não um relatório exaustivo. Se algo já está bem coberto pela memória automática (claude-mem/`MEMORY.md`), não repita aqui.
