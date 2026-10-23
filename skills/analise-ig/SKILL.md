---
name: analise-ig
description: Audita um plano de implementacao antes que ele vire codigo: procura o que esta errado, o que falta e o que pode melhorar. Reporta achados sem implementar, sem editar o plano e sem commitar. Use quando o usuario pedir "/analise-ig".
disable-model-invocation: true
---

# /analise-ig — Auditoria de um plano antes de executá-lo

Revisa um plano de implementação **antes** que ele vire código, procurando o que está errado, o que está faltando e o que pode melhorar. Reporta os achados; **não implementa nada, não edita o plano, não commita**. Quem decide o que fazer com os achados é o usuário.

Contraste com os comandos irmãos: `/execute-code-review-ig` audita o **diff** depois; `/analise-ig` audita o **plano** antes. Um achado aqui custa uma linha de texto; o mesmo achado depois custa uma fatia inteira refeita.

## 0. Modo da auditoria

Há dois modos, que **não** são intercambiáveis:

- **`/analise-ig` chamado diretamente pelo usuário** (padrão): execute os quatro eixos, inclusive **Oportunidades 🔵**. Não edite plano nem código; reporte e deixe o usuário decidir o que aplicar.
- **`modo=preflight-execute`**, passado explicitamente pelo `/execute-ig`: execute Código, Spec e Execução com o mesmo rigor, mas **não procure nem reporte oportunidades 🔵**. O `/execute-ig` tem autorização para corrigir todo 🔴/🟡 no plano antes de implementar; oportunidade é melhoria opt-in do usuário, nunca trabalho implícito da execução.

Se o modo não vier declarado, assuma o primeiro. Nunca chame uma passada parcial de “`/analise-ig`” completa.

## 1. Identificar o plano

Nesta ordem:

1. Um plano já no contexto da conversa.
2. Um caminho passado explicitamente pelo usuário.
3. O arquivo mais recente em `.cursor/plans/*.plan.md`.

Antes de usar a opção 3, registre `HEAD` e `git status --porcelain`. Se a árvore estiver suja e o plano não veio do contexto nem por caminho explícito, **não** selecione o mais recente: liste os candidatos e peça o caminho. Um plano escolhido por timestamp contra código em mutação não tem baseline auditável.

Se mais de um candidato for plausível, liste-os e pergunte. Não presuma.

Leia o plano **inteiro** — frontmatter (`name`, `overview`, `todos`) e corpo. O frontmatter é o que a execução realmente segue; um corpo bonito com `todos` frouxos é um plano frouxo.

## 2. Eixo Código — reconciliar o plano contra o repositório real

**É o eixo mais valioso; faça-o primeiro e nunca pule.** O modo de falha dominante deste projeto não é plano mal escrito — é plano escrito contra o que a ADR *diz* em vez do que o código *faz*.

Para cada afirmação factual do plano sobre o estado atual do código ("hoje não existe X", "os 4 hosts têm Y", "o handler já faz Z"), **abra o arquivo e confirme**. Grep, leitura direta, `git log` — não confie no texto do plano nem no da ADR.

Reporte:

- **Premissa falsa** — o plano afirma um estado que o código contradiz. (Precedente: o plano do ADR-0033 dizia "visibilidade por carteira"; o código a implementava por produto/ramo. Precedente: o ADR-0016 não registrava o `ClientSecret` de client confidencial que estava versionado.)
- **Já feito** — um `todo` que o código já satisfaz. Trabalho morto; corte.
- **Alvo inexistente ou movido** — arquivo, tipo, endpoint ou config que o plano cita e que não existe mais com aquele nome/caminho.
- **Colateral não mapeado** — outros pontos do código com a mesma forma do que está sendo corrigido, que o plano não lista (o defeito latente irmão). Se a correção é sistêmica, o plano precisa dizer isso.

## 3. Eixo Spec — o plano é o que a governança pediu?

Fontes na hierarquia do `CLAUDE.md` §3: a(s) ADR(s) em `docs/adr/` (mais recente/específica prevalece) → `docs/releases/<release-corrente>/scope.md` → `docs/roadmap/release-map.md` → as rules da área.

**Abra as rules da área explicitamente — aqui elas não chegam sozinhas.** Metade das rules deste repo se anexa por `globs` de código (`060` em `platform/backend/**/*.cs`, `050` em `**/*Api/**`, `052` em `Apps/**/Program.cs`, `070`/`080`/`090` nos `.ts`). O que você tem aberto agora é um `.plan.md` — **nenhum desses globs casa**, então você está julgando o plano só com as rules `alwaysApply`. Identifique a área que o plano toca, use o mapa da `005-documentation-context-hierarchy.mdc` para saber quais rules a governam, e **abra-as**. Um plano de backend julgado sem a `060` e a `050` em contexto é um plano não-analisado.

Reporte:

- **Requisito da ADR/scope ausente ou parcial** no plano.
- **Scope creep** — `todo` que ninguém pediu. Cite o que autorizaria (ou o vazio).
- **Fora da release corrente** — o plano puxa trabalho de release futura, contra o congelamento ("a maré sobe", T93).
- **Mudança estrutural sem ADR** — o plano decide algo que, pelo `CLAUDE.md` §2, exige ADR e aprovação do owner antes de virar código.
- **Custo fixo novo (T7)** — qualquer dependência paga, SaaS ou serviço gerenciado que o plano introduz sem autorização explícita do owner. Sempre bloqueante.
- **Violação de rule** — o plano instrui algo que uma rule documentada proíbe (ex.: meta-framework de telas de settings contra a `041`; mock fora de fronteira de sistema contra a `060`).
- **Vocabulário** — o plano usa termos aposentados (`Grupo`, `Owner`/"responsável", "onda", `Contact.Tags`, toggle soft/hard do ADR-0013 §4) em vez dos canônicos do `CLAUDE.md` §5.

## 4. Eixo Execução — o plano é executável como escrito?

Onde os planos deste repo historicamente vazam:

- **Gate de pronto ausente ou frouxo.** Existe `todo` de gates, e ele bate com a definição de pronto das rules — `110` §"Gate de pronto" e `060` §"Pronto ≠ `--filter`"? **Abra as rules e confira contra elas**, não contra a sua memória do que o gate era: é a fonte, e ela muda. Confira em especial os gatilhos condicionais (Integration, HostSmoke), que são o que os planos costumam esquecer.
- **Teste vácuo** e **defesa não exercitada.** Os dois critérios estão em `060` §"Desenho de teste — verde não é prova". Aplique-os ao que o plano **manda escrever**: para cada teste proposto, ele falharia se a correção não existisse? E, se o plano adiciona guard/fail-fast/limite/header, ele manda exercitar o mecanismo de fato (rodar o binário, ler o exit code, ver o 413) ou só manda escrever teste?
- **Seam não acordado.** A fatia é testável no ponto que o plano indica, ou o teste vai precisar de um mock fora de fronteira de sistema?
- **Fatia grande demais.** Um `todo` que só fecha depois de tocar backend, frontend, migração e config não é uma fatia — é um passo. Sugira o corte.
- **Ordem quebrada.** Dependência implícita entre `todos` (o item 5 precisa do 8). Reporte a ordem correta.
- **Migração/dado ausente.** Muda schema, RLS ou enum e não há `todo` de migração + `FORCE` nas filhas + backfill?
- **Contrato de API/frontend.** O plano muda contrato e não diz o que acontece com o consumidor?
- **Reversibilidade.** Se a fatia der errado no meio, dá para parar? Migração destrutiva sem `Down`?
- **Ambiguidade.** `todo` cujo "pronto" não é verificável ("melhorar", "ajustar", "revisar"). Todo `todo` tem critério de aceite objetivo.
- **Reuso não verificado.** O plano manda criar artefato novo (inclusive variável de ambiente ou chave de configuração) ou manda o dev preencher uma configuração sem o bloco **Reuso** da fatia (`plan-for-cursor` passe 12), ou com "nada encontrado" sem os termos da busca. Faça você uma busca curta pelo substantivo e pelo verbo do comportamento: se achar equivalente que o plano não viu, é 🟡 com o caminho; bloco ausente sem equivalente achado também é 🟡, porque o executor vai criar às cegas. Vale também no `modo=preflight-execute`.

## 5. Eixo Oportunidades — o que ficaria melhor

Execute este eixo **somente no `/analise-ig` chamado diretamente pelo usuário**. No `modo=preflight-execute`, escreva “Oportunidades: não avaliadas neste modo” e prossiga sem procurar nem propor melhoria opcional.

Não são defeitos; são melhorias que o usuário decide se quer. Rotule como opcionais e **não** as misture com os achados dos eixos 2–4.

Simplificação (o plano faz em três passos o que dá em um), reuso além do eixo 4 (o plano decidiu "criar novo" com justificativa, mas há um existente que valeria generalizar — cite o caminho), generalidade especulativa (abstração para necessidade que ninguém pediu — corte até ela aparecer), risco a mitigar barato.

## 6. Saída

**Antes de classificar, filtre contra o registro de resíduos.** Este repo documenta resíduos decididos em dois lugares canônicos: a tabela "Resíduos e decisões" do build-log do passo (`docs/releases/<release>/build-log/step-*.md`) e a seção de status/histórico da ADR do lote. **Resíduo documentado com decisão do owner não é achado** — reapresentá-lo com ID novo é o que faz auditoria orbitar em vez de convergir. Ele só volta ao relatório com **evidência nova, citada no achado** (ex.: o Worker sem `throw;` estava decidido como "tratar na rule 050"; a prova empírica do SH-13 — exit 0 neutraliza o guard, fix de uma linha — foi evidência nova legítima para reabrir). Sem evidência nova, no máximo mencione em "Verificado e OK": "resíduo X segue como decidido".

Classifique cada achado por severidade e **cite sempre a âncora**: o `todo` (por `id`) ou a seção do plano, e o arquivo real do repo quando o achado vier do eixo 2.

- 🔴 **Bloqueante** — executar assim produz a coisa errada, quebra governança ou introduz custo fixo. Não execute antes de resolver.
- 🟡 **Correção** — o plano funciona, mas com um furo (gate frouxo, teste vácuo, migração faltando). Corrija antes.
- 🔵 **Oportunidade** — melhoria opcional; decisão do usuário.

```markdown
## Análise do plano — <nome do plano>

**Plano:** <caminho>
**Modo:** <direto | preflight-execute>
**Baseline:** <HEAD> · <working tree limpa | suja, com resumo dos paths preexistentes>
**ADR(s)/scope de referência:** <…>
**Veredito:** pronto para executar | executar após as correções 🟡 | não executar (🔴 aberto)

### 🔴 Bloqueantes
<achado — âncora no plano — evidência no código — correção proposta>

### 🟡 Correções
<idem>

### 🔵 Oportunidades
<idem>

### Verificado e OK
<o que foi conferido contra o código e bateu — para o usuário saber o que NÃO precisa reconferir>

### Resultado por eixo
- Código: <achados ou “nenhum — afirmações e arquivos conferidos”>
- Spec: <achados ou “nenhum — ADR/scope/rules abertos”>
- Execução: <achados ou “nenhum — gates, testes e ordem conferidos”>
- Oportunidades: <achados | “nenhuma” | “não avaliadas neste modo”>
```

Se um eixo não produziu achado, diga isso explicitamente, com as fontes abertas ("Spec: nenhum achado — os 6 `todos` cobrem os 3 itens do ADR-0016"). Silêncio não se distingue de eixo pulado. Uma lista de confirmações de código **não** prova Spec, Execução ou Oportunidades.

Não invente achado para parecer útil: um plano bom sai daqui com veredito "pronto para executar" e a seção "Verificado e OK" preenchida.

## 7. Depois

No modo direto, termine perguntando ao usuário se ele quer que você **aplique as correções no arquivo do plano** — só edite o `.plan.md` sob pedido explícito. Nunca comece a implementar a partir de `/analise-ig`; quem executa é o `/execute-ig`.

No `modo=preflight-execute`, devolva a matriz completa ao `/execute-ig`; ele é responsável por resolver cada 🔴/🟡 antes do primeiro arquivo de produção ser editado.
