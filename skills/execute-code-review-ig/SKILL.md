---
name: execute-code-review-ig
description: Revisao do diff em dois eixos (Standards e Spec) contra as rules do repositorio e o plano. Use quando o usuario pedir "/execute-code-review-ig".
disable-model-invocation: true
---

# /execute-code-review-ig — Revisão em dois eixos (Standards + Spec)

Revisão do diff entre `HEAD` e um ponto fixo, em dois eixos separados:

- **Standards** — o código segue as rules documentadas deste repo (`.cursor/rules/`) e o baseline de smells abaixo?
- **Spec** — o código implementa fielmente o que o plano/ADR/scope que originou o trabalho pediu?

Rode as duas passadas **sequencialmente** (Standards, depois Spec) e reporte os achados separados, sob duas seções. Não mescle nem reordene achados entre eixos — um diff pode passar num eixo e falhar no outro, e misturar os dois esconde isso.

## 1. Fixar o ponto de comparação

Se o usuário não informou um ponto fixo (commit, branch, tag), pergunte — ou, se o trabalho veio de um plano identificável em `.cursor/plans/*.plan.md`, use o commit anterior ao início daquele plano.

Capture uma vez: `git diff <ponto-fixo>...HEAD` (three-dot, contra o merge-base) e `git log <ponto-fixo>..HEAD --oneline`. Confirme que o ponto resolve (`git rev-parse <ponto-fixo>`) e que o diff não está vazio antes de prosseguir.

## 2. Eixo Standards

Fontes, nesta ordem:

1. As rules de `.cursor/rules/` relevantes à área tocada — use o mapa em `005-documentation-context-hierarchy.mdc` para saber quais (`010`/`020`/`030`/`035`/`040`/`050`/`060` para backend, **+ `052` se o diff tocar `Program.cs`/composição de host Aspire**; `036`–`039`/`041`–`044`/`070`/`080`/`090` para frontend — `040` é exceção somente-backend, não confundir (ver `005`); `100` para contratos fullstack; `110` sempre).
2. O gate de pronto (`060-dotnet-code-style-tests.mdc` / `110-cursor-workflow.mdc` — "Pronto ≠ `--filter`") conta como standard documentado, não como smell: se a suíte inteira não rodou sem `--filter`, é achado de Standards, não julgamento.
3. O baseline de smells abaixo (Fowler, *Refactoring* cap. 3) — vale mesmo quando nenhuma rule documenta o assunto.
4. Se o `CLAUDE.local.md` do repo tiver uma lista de bloqueios recorrentes do owner, confira cada item que a área tocada alcança contra o diff. Item violado é achado de Standards, citando o número do item e a rule que ele aponta.

Duas regras ligam o baseline:

- **O repo sobrepõe.** Uma rule documentada sempre vence; onde ela endossa algo que o baseline marcaria, suprima o smell.
- **Sempre julgamento.** Cada smell é uma heurística rotulada ("possível Feature Envy"), nunca uma violação dura — e, como qualquer standard aqui, pule o que já é imposto por tooling (linter, analyzer, NetArchTest).

Cada smell: *o que é* → *como corrigir*; confira contra o diff:

- **Nome misterioso** — função, variável ou tipo cujo nome não revela o que faz/guarda. → renomear; se nenhum nome honesto aparecer, o design está confuso.
- **Código duplicado** — a mesma forma de lógica aparece em mais de um hunk/arquivo do diff, **ou o diff cria o que o repo já tem**: para cada tipo, método, componente, helper, variável de ambiente ou chave de configuração nova, faça grep fora do diff pelo substantivo e pelo verbo do comportamento; para configuração, também pelo valor que ela carrega e nos lugares listados no passe 12 da `plan-for-cursor` (`Smtp:Host` no `appsettings` é `Smtp__Host` no ambiente). → extrair a forma compartilhada e chamar dos dois lados, ou usar o existente. Se o plano decidiu **reusar** ou **estender** e o diff criou outro, é achado do eixo Spec.
- **Feature Envy** — um método que mexe mais nos dados de outro objeto do que nos próprios. → mover o método para onde estão os dados.
- **Data Clumps** — os mesmos poucos campos/parâmetros sempre viajam juntos (um tipo querendo nascer). → agrupar num tipo só.
- **Obsessão por primitivo** — um primitivo ou string representando um conceito de domínio que merece tipo próprio. → dar ao conceito seu próprio tipo pequeno.
- **Switches repetidos** — o mesmo `switch`/cascata de `if` no mesmo tipo se repete no diff. → substituir por polimorfismo, ou um mapa único compartilhado pelos dois pontos.
- **Shotgun Surgery** — uma mudança lógica força edições espalhadas em muitos arquivos do diff. → reunir o que muda junto num módulo só.
- **Divergent Change** — um arquivo/módulo é editado por vários motivos não relacionados. → dividir para cada módulo mudar por um motivo só.
- **Generalidade especulativa** — abstração, parâmetro ou hook adicionado para necessidade que o plano/ADR não pediu. → remover; volte a inline até uma necessidade real aparecer.
- **Message Chains** — navegação longa `a.B().C().D()` que quem chama não deveria depender. → esconder o percurso atrás de um método no primeiro objeto.
- **Middle Man** — classe/função que só delega adiante. → cortar, chamar o alvo real direto.
- **Refused Bequest** — subclasse/implementação que ignora ou sobrescreve a maior parte do que herda. → trocar herança por composição.

Reporte, por arquivo/hunk quando fizer sentido: (a) toda violação de rule documentada, citando a rule (arquivo + regra); (b) todo smell do baseline, nomeando e citando o trecho. Distinga violação dura (rule documentada) de julgamento (smell do baseline).

### Alcance de seletores novos

Para cada glob, regex, wildcard, enumeração de paths, export, DI, rota ou migration criado/alterado, calcule o conjunto alcançado e compare ao esperado pelo plano. Reporte apenas contagem, exceções e evidência curta; alcance diferente é achado de Standards e corrige antes do gate.

## 3. Eixo Spec

Este repo não tem issue tracker — a fonte da "spec" é a hierarquia real do `CLAUDE.md` §3:

1. O plano em `.cursor/plans/*.plan.md` que originou o trabalho, se identificável.
2. A(s) ADR(s) relacionada(s) em `docs/adr/` — a mais recente/específica prevalece.
3. O `scope.md` da release corrente (`docs/releases/<release-corrente>/scope.md`), se o plano não cobrir o requisito por completo.

Reporte: (a) requisitos do plano/ADR/scope que estão faltando ou parciais; (b) comportamento no diff que não foi pedido (scope creep); (c) requisitos que parecem implementados mas estão errados; (d) **testes do plano faltando ou parciais**. Cite o artefato (caminho do plano, número da ADR, ou linha do scope) em cada achado.

**Os testes que o plano pede são requisito deste eixo, não assunto só do TDD.** Percorra os ids da seção de testes do plano (`T1.1`, `T1.2`, `T4`…), **não** os testes presentes no diff: para cada id, ache a linha da asserção que cobre a obrigação. Teste que não existe não aparece no diff, e por isso só uma passada a partir do plano o encontra. Id sem asserção, ou coberto pela metade, é achado (d), e o eixo não sai "nenhum" enquanto houver um sem motivo declarado. Dentro do `/execute-ig`, o resultado desta passada é a tabela de rastreabilidade do relatório. O formato está em `.cursor/commands/execute.md`, passo 5, §Ciclo TDD.

Se nenhum dos três existir para o trabalho em questão, registre isso explicitamente ("sem plano/ADR/scope identificável para este diff") em vez de pular o eixo silenciosamente.

## 4. Saída

```markdown
### Standards
<achados, ou "nenhum">

### Spec
<achados, ou "nenhum">
```

Formato pensado para ser colado direto na seção "Code review" do relatório gerado por `/execute-ig`.
