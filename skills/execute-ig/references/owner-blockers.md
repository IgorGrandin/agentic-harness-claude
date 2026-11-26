# Bloqueios recorrentes do owner nas PRs do dev

Extraídos das revisões do Ricardo Stamato nas PRs 1495–1822 e na WI 3595 (levantamento de 2026-10-23), com o item 6
ajustado ao fluxo atual. Os itens 21 a 30 vêm das PRs de dev 1582–2116 (levantamento de 2026-11-13); o item 31, da convenção de erro do backend; os itens 32 a 46 e os precedentes novos dos itens 4, 9, 10, 23, 28 e 29, das PRs de dev 2121–2448 (levantamento de 2026-11-26). É a fonte única: os `CLAUDE.local.md` das pastas do BrixBroker só carregam a autorização de
implementar, e esta lista é lida sob demanda por `/execute-ig` (revisão de integração), `/revise` e
`/execute-code-review-ig`. Os números dos itens são citados pelo script e pelas skills: não renumere.

O Claude Code não carrega `.cursor/rules/*.mdc` sozinho: ao planejar, implementar ou revisar, **abra a rule citada**
e confira o diff contra cada item que a área tocada alcança.

Parte da lista é checada por script, que o `/execute-ig` (passos 5 e 7) e o `/revise` rodam:
`scripts/check-owner-blockers.ps1`. Ele **bloqueia** os itens 1, 3, 4 (migration publicada e RLS sem `FORCE`), 14, 21 (`$any`), 31 (`throw new` sem justificativa), 32 (número de ADR repetido) e 34 (design-system importando `core`), e **alerta** os itens 1 (remoção nomeada no plano ou junto com o arquivo), 2 (inclui `!important`), 3 (contrato novo fora dos tipos gerados), 4
(`DropColumn`/`DropTable` no `Up`), 9, 10 (frescor do gate, nunca bloqueia), 12, 13, 14 (`::ng-deep` coberto por justificativa vizinha), 21 (`as any`), 22, 24, 25, 33, 35, 36, 37, 38 e 39; 36 e 37 ficam UNVERIFIED quando não conseguem checar. Um hook no `.claude/settings.local.json` do projeto nega Edit/Write em `generated/*.types.ts` (item 3). Os
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
     (ADR-0045). O script só confere a que está no master; saber se a da branch já foi para um
     ambiente (build manual no dev2, por exemplo) é do dev, que não a edita depois disso. Migration que só
     existe na branch e nunca foi implantada pode ser editada, regerando `Designer` e snapshot
     (orientação do owner na PR 1772). Depois que o dev1 ou o dev2 aplicou a migration da branch, o EF não a
     aplica de novo: o que mudar vai numa migration nova (2448: RLS acrescentado numa migration já aplicada no dev1
     deixou o dev1 sem RLS);
   - tabela tenant-owned tem RLS `ENABLE` + `FORCE` + `WITH CHECK` (ADR-0009);
   - depois de trazer o master, confira o snapshot (ele mescla sem marcador de conflito) e a
     ordem do `migrations.lock`. Snapshot divergente se corrige com o arquivo regerado pelo teste de
     Architecture (`%TEMP%\ModelSnapshotDrift\`), não trocando blocos à mão (2195).
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
   de mutantes (vermelho visto) também da rodada de correção. Spec e plano também não apontam para o que
   ninguém mais abre: `tmp/` (está no `.gitignore`), `~/.claude/...`, `notes-*.md` local, link de OneDrive pessoal
   ou de artefato do claude.ai (2122, 2254, 2396, 2443). Import do Claude Design citado na spec é versionado (2254).
   Captura de tela vai anexada na PR nas larguras que a spec pede, e o vídeo mostra a ação, não só o resultado
   (2331, 2342, 2448: o vídeo mostrou a mensagem, mas não o clique em salvar).
10. **Traga o master antes de pedir revisão** (1822) e deixe o CI rodar de novo sobre o merge. PR que entrou no
    master depois da última run e mexe nos mesmos arquivos pede a 158 (ou a 167) de novo, mesmo sem conflito
    de texto (2193, 2195, 2254, 2316).
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
    (2116: "Tarefa: Parcela #N"). Casca de diálogo e item de lista locais voltam para o design-system: o mixin
    `dialog.host-shell-scrollable` fica e só se sobrescreve o que precisa (2254, rule `044`); a casca nova vira variante
    do `_broker-dialog-shell.scss` e a lista lateral usa `broker-timeline` (2448, rule `038`).
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
    Releia os comentários que o diff tocou contra o que o código faz agora. Vale para critério da spec que contradiz
    o teste (2254), decisão do dev que descreve outra coisa que o código (2423), plano com `todo` em `pending` e
    números velhos (2342) e build-log com status ou data desatualizados (2396).
29. **Defesa nova tem teste que falha sem ela** (1972: guarda do commit sem teste vácuo; 2004: `IncludeOrphans`;
    2049: gatilho voltando ao `BackfillAsync`; 1791: 403 real, não teste de arquitetura que procura texto no fonte).
    Mostre o vermelho ao remover a defesa, na PR, em texto (complementa o item 19; 2121, 2193). Quando a correção
    entrou num commit só, a descrição da PR diz quais testes falharam no master antes dela, com a mensagem (2423).
30. **Lógica nova sem teste não entra como "depois"** (2113: `detailLoadGeneration` e o AC 39 sem assert de
    `LastInboundSequence` nem de não lidas; 2031: três testes do AC 25; 1972: retry de tempo real).

## Acrescentados em 2026-11-26

31. **Falha esperada sai pelo `Result`, não por exceção.** Regra de negócio, validação, não encontrado, conflito e
    permissão retornam `Result.Failure(Error.Validation|NotFound|Conflict|Forbidden|Failure(code, message, params))`,
    e o endpoint responde com `ToProblemDetails()` (`BuildingBlocks.Api/Extensions/ResultExtensions.cs`). É esse
    caminho que leva o `errorCode` estável e o `errorParams` ao frontend, que mostra a copy pelo
    `resolveErrorMessagePt` (ADR-0006, ADR-0032, ADR-0043). Exceção que escapa cai no `GlobalExceptionHandler` e vira
    500 genérico, sem código: a tela não tem o que mostrar. `throw` continua certo para invariante e erro de
    programação, argumento inválido, falha de infraestrutura e job em background sem resposta HTTP; nesses casos,
    um comentário `//` logo acima do `throw` (ou da instrução, ou do `if`, que o contém), ou no fim da própria linha,
    diz por que o `Result` não serve, como no `::ng-deep` do item 14. Doc XML (`///`) e comentário no fim de outra
    instrução não contam. O script bloqueia `throw new` acrescentado em `*.Application/Features/**` e
    `*.Api/Endpoints/**` do backend sem esse comentário.

### Checados por script (PRs 2121–2448)

32. **Número de ADR não se repete** (2267: a 0075 da semente colidiu com a 0075 de Origem do contato, que entrou
    no master antes). ADR nova cujo número já existe no master com outro nome é renumerada para o próximo livre, com
    todas as citações (`git grep -n "<número>"`) e a linha do vocabulário. O script bloqueia.
33. **Marca de decisão pendente não chega ao merge** (2267, 2303, 2423). "Aval do owner pendente", "pendente de
    confirmação do owner" e afins viram "decisão do owner, <data>" (com a thread) quando ele decide, ou a pendência
    fica listada na descrição da PR. Procedência de decisão cita thread que existe (2303: thread com o comentário
    apagado). O script alerta a marca em linha acrescentada de `docs/`, `backlog/` e `.cursor/plans/`.
34. **O design-system não importa `core`** (2448: `broker-select` importava o filtro sem acento de `core`). A
    dependência vai de `core` e das features para o design-system, nunca ao contrário: a função fica no próprio DS ou
    entra por input. O script bloqueia.
35. **Feature não mira classe interna do Material** (`.mat-mdc-*`, `.mdc-*`; 2129, rule `036`). O Material fica
    encapsulado no design-system: use a API do `broker-*`, ou aponte a lacuna. O script alerta.
36. **Código de erro novo tem copy** (2296, 2314, 2429; complementa o item 31). Todo `errorCode` novo do backend entra
    no `ERROR_COPY_PT` (ou na copy do admin-web) na mesma PR, e copy que cita o nome antigo de um campo acompanha a
    troca. O script alerta o código novo que não aparece em nenhum arquivo `*error-copy*.ts` do frontend.
37. **Tabela nova com RLS tem teste de `FORCE`** (2254), no molde de `ImportBatchesIntegrationTests`: `relrowsecurity`
    e `relforcerowsecurity` verdadeiros, lidos no catálogo do Postgres. O script alerta a tabela que nenhum teste
    com `relforcerowsecurity` cita.
38. **Migration nova com data anterior à última do master** (2429, 2195). Ela mescla sem conflito, mas o snapshot
    precisa ter as colunas dos dois lados e nenhuma mudança de modelo pendente: rode a Architecture com o master
    mergeado. O script alerta.
39. **PR com Work Item vinculado** (2314: a branch tinha o número, a PR não tinha o vínculo). O script alerta pela
    consulta da PR no Azure DevOps.

### De julgamento (PRs 2121–2448)

40. **Nada fora do processo com transação ou trava aberta** (ADR-0074 §1; 2195, 2296, 2429). Leitura que passa por
    `HybridCache`, Redis, Keycloak, diretório de colaboradores ou HTTP acontece **antes** de abrir a transação ou
    tomar o `FOR UPDATE`; dentro dela, só a revalidação. Junto vêm:
    - `FOR UPDATE` sem transação aberta não trava nada depois do próprio comando (2195);
    - efeito que precisa gravar junto com a operação (fila, outbox, marca de tentativa) usa o
      `unitOfWork.ExecuteAsync`, que alista os `DbContext` dos módulos na mesma conexão; `BeginTransactionAsync` de
      um contexto só deixa o outro de fora (2195);
    - transação dentro de transação quebra em tempo de execução: quando dois caminhos tomam travas, um só é dono
      da transação e a ordem das travas é a mesma em todo caminho (2429, licença e depois sufixo).
41. **A regra que a tela bloqueia vale também no backend** (2296: adiar Parcela só estava bloqueado na tela). A
    recusa fica no comando ou no domínio, com código de erro próprio (item 31) e copy (item 36), e o teste espera a
    recusa.
42. **GET não grava** (2429: o GET de disponibilidade reservava o endereço). Quem repete um GET (retry, ferramenta,
    cache) não espera escrita. Sem o dado, o GET devolve o erro que a tela já trata; a reserva fica nos comandos.
    Teste contra Postgres prova que nada foi gravado.
43. **Teste de concorrência força a sobreposição** (2193). `Task.WhenAll` com fake síncrono pode passar sem a trava:
    segure a primeira passada na janela que a trava protege (como `HoldProvisioningLockAsync`) ou mostre o mutante
    vermelho. O teste par "sem a trava, a outra conexão trava a linha sem esperar" também vale (2195).
44. **Falha de carga não vira estado falso na tela** (2396: equipes que não carregaram acendiam "sem equipe" em
    todo tipo de seguro). Com o `error()` da fonte preenchido, o que depende dela não acende alerta nem mostra
    "vazio"; o bloco de erro já avisa. Erro que não se resolve tentando de novo (prontidão, bloqueio) tem rótulo e
    motivo próprios, sem "Tentar de novo" (2429: `provider_route_unavailable`).
45. **A descrição da PR é o que o owner lê** (2129, 2303, 2403, 2423). Lista tudo o que pede ratificação, inclusive
    mudança no design-system, que não pode ficar só na spec; diz em uma linha o que a PR entrega; não afirma o que
    o diff contradiz ("o diff não remove nenhum `it`", "sem prova nova") e tira o bloco de pendências quando o owner
    decide. Spec e card andam juntos (ADR-0039 §1, 2429).
46. **Teste que não prova nada sai ou é reescrito** (complementa os itens 19 e 29):
    - mock que devolve exatamente o que a asserção espera, sem passar por código que mudou (2254);
    - `NotBe(code)` fora do HostSmoke passa com qualquer resultado: afirme o sucesso ou o código esperado (2403);
    - critério que depende de banco não se prova pelo HostSmoke, que roda sem banco e só vê a ausência de 401/403/5xx
      (2403: "Operações cria nota" pedia teste de integração);
    - teste que fixa um valor de enum entre módulos cobre todos os membros num `[Theory]` (2195: gênero como `string`).
