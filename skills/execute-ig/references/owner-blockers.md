# Bloqueios recorrentes do owner nas PRs do dev

Extraídos das revisões do Ricardo Stamato nas PRs 1495–1822 e na WI 3595 (levantamento de 2026-10-23), com o item 6
ajustado ao fluxo atual. Os itens 21 a 30 vêm das PRs de dev 1582–2116 (levantamento de 2026-11-13). É a fonte única: os `CLAUDE.local.md` das pastas do BrixBroker só carregam a autorização de
implementar, e esta lista é lida sob demanda por `/execute-ig` (revisão de integração), `/revise` e
`/execute-code-review-ig`. Os números dos itens são citados pelo script e pelas skills: não renumere.

O Claude Code não carrega `.cursor/rules/*.mdc` sozinho: ao planejar, implementar ou revisar, **abra a rule citada**
e confira o diff contra cada item que a área tocada alcança.

Parte da lista é checada por script, que o `/execute-ig` (passos 5 e 7) e o `/revise` rodam:
`scripts/check-owner-blockers.ps1`. Ele **bloqueia** os itens 1, 3, 4 (migration publicada, RLS sem `FORCE`, migration
da branch editada depois do deploy no dev2), 10, 14 e 21 (`$any`), e **alerta** os itens 2 (inclui `!important`), 4
(`DropColumn`/`DropTable` no `Up`), 9, 12, 13, 21 (`as any`), 22, 24 e 25. Um hook no `.claude/settings.local.json` do projeto nega Edit/Write em `generated/*.types.ts` (item 3). Os
demais itens são de julgamento: o script não os enxerga.

## Bloqueiam merge

1. **Nunca apague teste existente** (PRs 1689, 1821). Ao reescrever um arquivo de teste, some o
   teste novo ao lado dos antigos. Antes da PR, `git diff origin/master -- <arquivos de teste>`
   não pode remover teste. Se o comportamento saiu de propósito, o plano lista o nome exato de
   cada teste removido e o motivo: nomear só o arquivo não basta.
2. **PR de feature não muda lib compartilhada nem texto fora do escopo** (1550, 1643, 1821).
   `design-system`, `layout`, `core`, tokens e estilos globais ficam como estão. O ajuste vai
   no SCSS da tela ou numa WI própria. Atributo ou artefato sem consumidor sai, inclusive dependência
   nova no `package.json` que nada importa (2001, `@tiptap/extension-link`). Regra global com `!important`
   ou `@media` que muda o shell alcança todos os apps (1776, 1714): escopo na tela.
3. **`broker-api.types.ts` é gerado** (1821; citada pelo owner como rule `100`, que ainda não menciona o gerador). Suba a API, rode `npm run gen:broker-api`
   e não edite o arquivo à mão. Depois troque os tipos declarados à mão por `Schemas[...]`.
4. **Migrations** (1689, 1772, 1822):
   - DROP/contração vai em migration separada, num deploy posterior (ADR-0049 §8);
   - migration já aplicada em ambiente compartilhado não é editada nem removida: crie uma nova
     (ADR-0045). Vale para a que está no master e para a da branch já publicada no dev2 por build
     manual. Migration que só existe na branch e só rodou localmente pode ser editada, regerando
     `Designer` e snapshot (orientação do owner na PR 1772);
   - tabela tenant-owned tem RLS `ENABLE` + `FORCE` + `WITH CHECK` (ADR-0009);
   - depois de trazer o master, confira o snapshot (ele mescla sem marcador de conflito) e a
     ordem do `migrations.lock`.
5. **Admin-web nunca lê nem altera dados de corretora** (WI 3595). Contato que já teve
   oportunidade não pode ser excluído.

## Processo e documentação

6. **A decisão é do dev; o owner ratifica ou rejeita na PR** (fluxo vigente, ajustado em 2026-11-11; o texto anterior pedia aprovação prévia do owner, que não existe mais). O dev decide, registra a decisão (`D<n>`, com o porquê) e a deixa visível na PR. Decisão que diverge do texto da spec ou de um critério, ou que mexe em texto enviado ao cliente, spec, ADR, segurança ou LGPD, entra na lista "Decisões que divergem" do bloco de evidência. Escreva "decisão do dev, a ratificar pelo owner na PR"; só escreva "ratificada pelo owner" depois que ele disser isso na thread (1550, 1689, 1772, 1822). Pedido relatado por terceiro não é decisão do owner (2049); "decisão do Gabriel, aguardando aval" na spec vira "aprovação do owner" (1783); a lista de decisões e a descrição da PR acompanham cada rodada (1972, 2113).
7. **ADR** (1689, 1772, 1822; `CLAUDE.md` §8): não reescreva o texto de uma decisão do owner. O
   estado atual vai no bloco "Status — o que vale hoje", sem apêndice que se acumula.
8. **Documentação bate com o código** (1689, 1772, 1821): ADR, spec, `scope.md` e
   `acceptance-criteria.md` descrevem o que foi entregue. IDs de decisão não se repetem.
9. **Evidência fica onde o owner consegue verificar** (1689, 1822): anexada à WI, commitada em
   `docs/releases/…` ou colada na PR em texto. Nunca só um caminho em `%TEMP%`. Inclua a tabela
   de mutantes (vermelho visto) também da rodada de correção.
10. **Traga o master antes de pedir revisão** (1822) e deixe o CI rodar de novo sobre o merge.
11. Item que o owner moveu para outra WI não é tocado nesta PR (1689, 2116: "não suba mais nada nele"). Plano de ferramenta
    ou trabalho de outra frente vai em branch separada (1776); pedido de editor ou anexo vira WI nova, não se implementa
    aqui (2113).

## Frontend

12. **Design system prevalece sobre o mockup** (1821, rules `038`/`070`; decisão verbal do owner
    no editor de templates da WI 2574).
    - Use os `broker-*` como eles são. O mockup define estrutura e conteúdo, não a estilização de
      cada controle: se o controle do mockup tiver outra cara, fica a cara do `broker-*`.
    - Não use `::ng-deep` nem override de SCSS para fazer um `broker-*` parecer com o mockup:
      quebra a rule `070` e estoura o budget de SCSS do componente.
    - Exceção: falta **comportamento** que o `broker-*` não entrega sem muita alteração (ex.:
      `datalist`, contador do textarea). Aponte a lacuna na PR; ela vira WI para estender o
      design system (WI 3772). Diferença visual sozinha não é lacuna.
13. Cores via `var(--md-*, #fallback)`, nunca hex fixo (1643, 1821). As cores do balão do WhatsApp
    podem ficar num bloco comentado.
14. `::ng-deep` só com justificativa escrita no código (1821, rule `070`). Caso aceito: HTML
    injetado sem o escopo do componente.

## Backend e testes

15. Efeito colateral depois de persistir (notificação, evento) é best-effort: `try/catch` +
    `LogWarning`, para não virar 500 e envio duplicado (1689).
16. Entrada recusada não some em silêncio: registre na conversa, sem dado pessoal (CPF) (1772).
17. Todo caminho que cria Contact ou Opportunity grava a auditoria do tenant (1772).
18. Consulta leva o predicado `TenantId` mesmo com RLS (1821, rule `052`).
19. Teste precisa conseguir falhar (1821, rules `050`/`060`):
    - afirme o conteúdo, não só `IsSuccess`;
    - "sem chamar X" exige X montado e observável;
    - HostSmoke tem o caso de controle (o papel autorizado não toma 403), além do 403;
    - o que o plano promete como `[Theory]` é `[Theory]`.
20. Resíduo criado e removido dentro da própria branch (conversor, normalizador) sai junto (1772).

## Acrescentados em 2026-11-13 (PRs de dev 1582–2116)

21. **Sem `$any` nem `as any`** (2113: `$any($event.target)` em `email-inbox.page.html`). Tipe o handler no componente:
    o template passa `$event` e o método recebe o tipo certo. O script bloqueia `$any(`; `as any` só alerta.
22. **Modal novo usa `broker-dialog` direto, não `lc-dialog`** (2113, rule `044`).
23. **Componente existente antes de classe própria** (1972: `.bell-text-button` virou `broker-button`,
    `.bell-spinner` virou `broker-progress-spinner`). Texto fixo de componente vai para a copy do projeto
    (1972: `NOTIFICATION_BELL`); `aria-label` descreve o que o controle faz, sem concatenar rótulo de tela
    (2116: "Tarefa: Parcela #N").
24. **Seletor posicional é frágil** (1972: `nth-child` em `_notification-sheet.scss`). Use classe.
25. **Teste de UI não lê CSS computado em jsdom** (2116: `getComputedStyle`; o próprio plano dizia para não ler).
    Afirme classe ou atributo e meça o layout num navegador de verdade (1783: 1440/768/375, em texto na PR).
26. **O fixture do teste do consumidor é a saída real do produtor** (2113: o spec usava `src` que o backend nunca
    gera, e passava). Conferir o produtor faz parte da revisão, não só o teste verde.
27. **Corpo sem o campo ou `null` nunca vira 500** (1827; 2049 cobra o mesmo nas rotas sem `.WithValidation<>`).
    Cada rota ganha teste com o corpo sem o campo, esperando 400 com o código, e o teste tem de falhar se o
    tratamento sair. O helper de validação é único: cópia idêntica por módulo (1827: 6 `ValidateToProblemAsync`) sai.
    Mensagem de erro de contrato segue a rule `060` (1791: `Message` em português).
28. **Comentário, spec e plano não contradizem o código** (2113: comentário de `CommunicationsWorkerCompositionTests`;
    2031: comentário de teste "item pendente de outra corretora"; 2049: "continuam 501"; 2116: "A1-02" que não existe).
    Releia os comentários que o diff tocou contra o que o código faz agora.
29. **Defesa nova tem teste que falha sem ela** (1972: guarda do commit sem teste vácuo; 2004: `IncludeOrphans`;
    2049: gatilho voltando ao `BackfillAsync`; 1791: 403 real, não teste de arquitetura que procura texto no fonte).
    Mostre o vermelho ao remover a defesa, na PR, em texto (complementa o item 19).
30. **Lógica nova sem teste não entra como "depois"** (2113: `detailLoadGeneration` e o AC 39 sem assert de
    `LastInboundSequence` nem de não lidas; 2031: três testes do AC 25; 1972: retry de tempo real).
