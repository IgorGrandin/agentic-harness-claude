---
name: my-execute-tdd
description: TDD no Broker: onde os testes vivem, fronteira de mock, anti-padroes e o loop red-green. Consulte antes e durante o loop. Use quando o usuario pedir "/my-execute-tdd" ou durante uma fatia TDD.
disable-model-invocation: true
---

# /my-execute-tdd — Test-Driven Development no Broker

TDD é o loop red → green. Esta skill cobre o que **não** está na `060`: onde os testes vivem (seams), a fronteira de mock adaptada ao Broker, os anti-padrões e as regras do loop. Consulte antes e durante o loop, não depois.

**A `060-dotnet-code-style-tests.mdc` é a fonte, e ela chega sozinha** (glob em `platform/backend/**/*.cs`): frameworks, Arrange-Act-Assert, nomenclatura (`Metodo_DeveResultado_QuandoCondicao`), "teste comportamento, não implementação interna", o que exige NetArchTest, o §"Desenho de teste — verde não é prova" e a definição de pronto. Nada disso é repetido aqui — se divergir, a rule vence.

Antes de explorar o código, leia `CLAUDE.md` §5 ("Vocabulário canônico") para os nomes de teste e o vocabulário de interface baterem com a linguagem de domínio do projeto, e respeite as ADRs (`docs/adr/`) da área que está sendo tocada.

## O que é um bom teste

Testes verificam comportamento através de interfaces públicas, não de detalhes de implementação. O código pode mudar inteiramente; os testes não deveriam precisar mudar junto. Um bom teste lê como uma especificação — "usuário consegue fazer checkout com carrinho válido" diz exatamente qual capacidade existe — e sobrevive a refactors porque não se importa com estrutura interna.

```csharp
// BOM: testa comportamento observável, através da interface pública
[Fact]
public async Task Checkout_ComCarrinhoValido_RetornaConfirmado()
{
    var cart = CreateCart();
    cart.Add(product);
    var result = await checkoutService.Checkout(cart, paymentMethod);
    result.Status.Should().Be(CheckoutStatus.Confirmed);
}

// RUIM: acoplado a detalhe de implementação
[Fact]
public async Task Checkout_ChamaPaymentServiceProcess()
{
    var mockPayment = Substitute.For<IPaymentService>();
    await checkoutService.Checkout(cart, payment);
    await mockPayment.Received(1).Process(cart.Total);
}
```

Um teste pode ser honesto na forma e ainda não provar nada — tautológico, vácuo. Os três modos de falha estão em `060` §"Desenho de teste — verde não é prova"; leia-os antes de escrever a primeira asserção.

## Seams — onde os testes vivem

Um **seam** é a fronteira pública testada: a interface onde você observa comportamento sem entrar por dentro. Testes vivem em seams, nunca contra internals.

**Teste só em seams acordados previamente.** Antes de escrever qualquer teste, escreva os seams sob teste e confirme com o owner. Nenhum teste é escrito num seam não confirmado. Não dá para testar tudo — acordar os seams antes é o que faz o esforço de teste cair nos caminhos críticos e na lógica complexa em vez de em cada edge case.

Pergunte: "qual é a interface pública, e quais seams devemos testar?"

## Fronteira de mock (adaptada ao Broker)

Mocke só nas **fronteiras de sistema** — nunca collaborators internos, nunca nada que o próprio módulo controla.

**Backend (.NET):**

- Mockar com NSubstitute só fronteiras externas reais: Keycloak/Identity, Redis, S3/MinIO, provedores de e-mail e WhatsApp Cloud API, integrações de seguradora (`services/carrier-integration-service`).
- **Não mockar** domain services, repositórios ou qualquer collaborator do próprio módulo (`Insurtech.<Modulo>.*`) — se o teste precisa disso, é sinal de que o seam está errado ou é implementation-coupled.
- Testes de integração usam Postgres real via Testcontainers, nunca mock de `DbContext` ou de RLS — RLS/visibilidade só se prova contra banco real (ver `Insurtech.Integration.Tests`).

**Frontend (Angular):**

- `HttpTestingController` na fronteira HTTP — é o único ponto de mock esperado.
- Não mockar serviços Angular internos do próprio app/lib (`core`, `shared`, `libs/features/**`).
- Cada endpoint como função própria e mockável, não um fetcher genérico com lógica condicional dentro do mock.

## Anti-padrões

- **Implementation-coupled** — mocka collaborator interno, testa método privado, ou verifica por canal lateral (consultar o banco direto em vez de usar a interface). O sinal: o teste quebra num refactor sem mudança de comportamento.
- **Tautológico** e **vácuo** — os dois vivem em `060` §"Desenho de teste — verde não é prova". Não são anti-padrões do loop: são defeitos do teste em si, e a rule é a fonte.
- **Horizontal slicing** — escrever todos os testes antes de toda a implementação. Testa a *forma* imaginada, não comportamento real; os testes ficam insensíveis a mudanças reais; e você trava a estrutura do teste antes de entender a implementação. É o oposto do que `110-cursor-workflow.mdc` já cobra ("prefira pequenas alterações incrementais e revisáveis"). Trabalhe em **fatias verticais**: um seam → um teste → uma implementação mínima → repita, cada teste reagindo ao que o ciclo anterior ensinou.

## Regras do loop

- **Red antes de green.** Escreva o teste que falha primeiro, depois só o código suficiente para passar. Não antecipe testes futuros nem adicione features especulativas. **O red é a prova de que o teste não é vácuo** — teste que nasce verde antes da implementação denuncia o seam errado; pare e reescolha (`060` §"Desenho de teste").
- **Defesa se prova disparando, não passando.** Se a fatia adiciona guard, fail-fast, limite, rate limit, header ou authz, o red/green não fecha o item — aplique `060` §"Desenho de teste": provoque a condição real, observe a consequência real.
- **Uma fatia por vez.** Um seam, um teste, uma implementação mínima por ciclo.
- **Refactor não é parte do loop.** Pertence ao estágio de revisão (`/my-execute-code-review`), não ao ciclo red → green.
- **Iteração rápida durante o loop pode usar `--filter`/watch mode** — é ferramenta de debug, não define "pronto". A definição de pronto (suíte inteira sem `--filter`) está em `060-dotnet-code-style-tests.mdc` e `110-cursor-workflow.mdc` — não é redefinida aqui, só se aplica no fim, antes do `/my-execute-code-review`.

## Saída de teste — contexto mínimo

Direcione output verboso para `%TEMP%\claude-handoffs\Broker\test-logs\` e guarde o caminho no relatório. Em sucesso, leia só comando, duração e resumo final. Em falha, busque primeiro `FAIL`, `ERROR`, `Unhandled`, `Expected` e abra apenas trechos curtos relevantes; então reproduza com o menor teste. O gate final continua inteiro: compactar a leitura nunca reduz o escopo.

Frameworks: backend, ver `060` (é a fonte, e chega sozinha). Frontend — TestBed com `imports` para standalone components, `HttpTestingController`, `fakeAsync`/`tick`/`whenStable` em vez de `setTimeout`; convenções em `090-angular-routing-performance-tests.mdc`.
