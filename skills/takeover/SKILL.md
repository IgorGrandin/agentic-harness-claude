---
name: takeover
description: Lê o documento de handoff mais recente (ou um indicado) e retoma o trabalho de onde a sessão anterior parou. Use quando o usuário pedir "/takeover" no início de uma janela nova.
argument-hint: "slug ou data do handoff a retomar (opcional — padrão: o mais recente)"
disable-model-invocation: true
---

Localize o handoff em `%TEMP%\claude-handoffs\Broker\`: se o usuário passou argumento, procure por slug/data correspondente; senão pegue o arquivo mais recente. Se houver mais de um candidato plausível e nenhum argumento resolver a ambiguidade, liste-os e pergunte qual retomar. Se não houver nenhum, avise o usuário — não invente um estado de retomada.

Leia o documento inteiro.

Antes de agir, confira rapidamente se o estado ainda bate com a realidade: `git status`/`git log` desde o timestamp do handoff; se o handoff aponta um plano do Cursor ou ADR específico, dê uma olhada rápida para confirmar que a descrição ainda procede. Não é uma auditoria completa — só o suficiente para não retomar algo que já mudou ou já foi concluído enquanto a sessão estava fechada.

Apresente ao usuário um resumo curto: onde paramos, o que (se algo) mudou desde o handoff, e a próxima ação proposta. Espere confirmação antes de prosseguir — não presuma autorização para agir (contrato "você propõe, o owner decide", `CLAUDE.md` §2).

O arquivo de handoff é descartável: depois de retomado com sucesso, pode ser ignorado ou apagado — não precisa de arquivamento formal.
