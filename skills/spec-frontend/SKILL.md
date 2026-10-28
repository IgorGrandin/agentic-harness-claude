---
name: spec-frontend
description: Transforma um mockup do Claude Design (import datado em platform/frontend/_imports/claude-design/) numa seção de spec de front-end pronta para anexar a uma task em backlog/tasks/ — extrai cores, tamanhos, espaçamentos, tipografia e comportamento, reconcilia cada valor com os tokens do design-system do projeto, normaliza equivalências exatas sozinha e leva as divergências ao dev para decidir — o que for design-system/ADR vai ao owner pela discussão da WI. Use quando o pedido mencionar mockup, Claude Design, spec visual ou de front-end, cores/tamanhos/estilos de uma task, ou reconciliar um design com o design-system.
---

# /spec-frontend — mockup do Claude Design → seção de spec

Repositório alvo: **Broker** (raiz do seu clone; todos os caminhos abaixo são relativos a ela).

## Por que esta skill existe

O Cursor implementa lendo a spec do repo. Um mockup publicado como Artifact do Claude Design é invisível para ele: a task [3227] citava o mockup só como linha de referência, e o resultado seria o Cursor herdando estilos existentes e improvisando o resto — o mockup só virando achado na auditoria, depois do código escrito.

Esta skill fecha esse buraco: o visual vira **texto versionado no repo**, com cada valor citando um token do design-system ou um literal que você aprovou. Honra a seta `spec → código` (CLAUDE.md §3) e o ADR-0011:61 — *o artefato do Claude Design é insumo aprovado, não fonte da verdade*.

## Entradas obrigatórias

1. **Import datado:** `platform/frontend/_imports/claude-design/<slug>/<YYYY-MM-DD>/` (o export fica em `original/`)
2. **Task alvo:** `backlog/tasks/<id>-<slug>.md`
3. **Recorte:** quais telas/componentes do mockup interessam a esta task

**Faltando qualquer um dos três, pergunte antes de ler qualquer arquivo.** O recorte é o que mais escapa e é o mais caro: sem ele você lê o mockup inteiro. No único import existente hoje, isso é `styles.css` com 1176 linhas mais ~3.400 linhas de `.jsx` — mais caro que a task que você está especificando.

Se o import ainda não existe no repo, **pare e peça ao dev que exporte**. Você não escreve em `platform/**` (ver Guardrails).

## Procedimento

### 1. Recorte antes de leitura

Nenhum arquivo do mockup é lido inteiro. Confirme com o dev quais elementos entram e trabalhe só neles.

### 2. Extrair do mockup por Grep dirigido

```
# tokens que o mockup declara
Grep "^\s*--[a-z]" em <import>/original/styles.css

# regras das classes do recorte (uma por vez, não todas de uma vez)
Grep "\.<classe>[\s{,:]" -A 15 em <import>/original/styles.css

# comportamento: estados e interação, não markup
Grep "onClick|onMouseEnter|onFocus|useState|aria-|role=" em <import>/original/app/<arquivo>.jsx
```

Se o export vier como HTML único (`.dc.html` ou `index.html`), os mesmos greps valem sobre o `<style>` embutido.

### 3. Ler a fonte canônica do projeto — conjunto fechado e barato

| Arquivo | Quando | Tamanho |
|---|---|---|
| `platform/frontend/libs/design-system/src/lib/theming/_tokens.scss` | **sempre**, íntegro | 110 ln |
| `.../theming/_palettes.scss` | só para resolver hex de marca do core M3 | 137 ln |
| `.scss` do componente que a task altera | quando a task altera um componente existente | ~150 ln |

`_tokens.scss` é a fonte de verdade: 78 declarações — cor, `--shape-*` (raio), `--fs-*` (tipografia), `--elev-*` (sombra), `--motion-*`, e as medidas de layout `--sidebar-w`, `--sidebar-w-collapsed`, `--topbar-h`.

### 4. Classificar cada valor em três baldes

| Balde | Critério | Ação |
|---|---|---|
| **A — já é token** | o mockup usa `var(--x)` e `--x` existe no `_tokens.scss` | cita o token; nada a decidir |
| **B — literal equivalente** | valor literal **idêntico** a um token, após normalizar | **normaliza sozinha**; uma linha na tabela |
| **C — sem equivalente** | nenhum token tem esse valor | **para e pergunta ao dev** |

**Como normalizar, com precisão:**

- **Referência por nome vence.** Se o mockup escreve `var(--md-primary)` e `--md-primary` existe no projeto, é balde **A** — não resolva hex. Os nomes coincidem porque os tokens do projeto nasceram deste mesmo mockup.
- **Hex cru:** normalize para minúsculo e 6 dígitos (`#FFF` → `#ffffff`), depois compare com os hex **literais** do `_tokens.scss` (`--md-success`, `--md-warning*`, `--broker-instagram`, `--broker-whatsapp`). Não achou? As cores do core M3 (`--md-primary`, `--md-surface`, …) são alias de `--mat-sys-*` e não têm hex ali — resolva pelo `_palettes.scss` antes de mandar para C.
- **Medidas:** compare após normalizar unidade; `rem` só converte para `px` assumindo base 16px, e **declare a suposição** quando usar.

**Equivalência é igualdade, nunca semelhança.** "Parecido" cai em C com o delta medido (ex.: mockup `13px`, token mais próximo `--fs-sm: 12px`, delta 1px). É o que impede a skill de achatar a intenção do design em silêncio.

**Cada item do balde C vai ao dev com três saídas nomeadas:**
1. aproximar do token mais próximo — com o delta explícito;
2. criar token novo — vira decisão de design-system, possivelmente ADR: é do **owner**, e vai como pergunta na discussão da WI;
3. aceitar o literal — com a justificativa registrada na tabela.

Agrupe itens C do mesmo tipo numa pergunta só (todos os espaçamentos juntos, todas as cores juntas). Uma pergunta por valor cansa e é onde o erro por fadiga entra.

### 5. Emitir a seção no formato da casa

As tasks do repo têm anatomia fixa de 7 seções: `## Objetivo`, `## Contexto`, `## Escopo`, `## Critérios de aceite`, `## Área de impacto esperada`, `## Coordenação com outras tasks`, `## Referências de arquitetura`.

**A saída encaixa nelas.** Nunca crie um H1, nunca um bloco paralelo às 7.

**a) Para `## Escopo`** — subseção nova:

```markdown
### Especificação visual

Origem: `_imports/claude-design/<slug>/<data>/`. Valores não especificados aqui
seguem o token equivalente do design-system — não hardcodar.

- **<elemento>**: altura `<v>`, padding `<v>`, raio `var(--shape-md)`,
  fundo `var(--md-surface-container)`, texto `var(--md-on-surface-variant)`,
  fonte `var(--fs-sm)`
- **<elemento> — estado ativo**: fundo `var(--md-secondary-container)`, …
- **<elemento> — "Em breve"**: opacidade `0.55`, cursor padrão, sem tooltip
```

**b) Para `## Critérios de aceite`** — itens numerados e observáveis, no estilo já usado em `2601-menu-lateral-recolher-por-clique.md` e `3092-refinar-visual-tela-login.md`. Um AC por propriedade **verificável**, não um AC por token.

**c) Para `## Contexto`** — a tabela de reconciliação, que é o registro de *por que* os valores são esses:

```markdown
#### Reconciliação com o design-system — <data>

| Elemento | Mockup | Design-system | Resolução |
|---|---|---|---|
| badge "Em breve" | `#ffdfa1` | `--md-warning-container` (`_tokens.scss:49`) | normalizado para o token |
| gap do grupo | `10px` | sem escala de espaçamento | **dev (<seu nome>, <data>):** literal aceito |
```

**d) Para `## Referências de arquitetura`** — link relativo para a pasta datada do import.

### 6. Escrever na task

Só **depois** que o dev aprovar a tabela do passo 4. Escreva direto no arquivo em `backlog/tasks/` — inserindo cada bloco na seção que lhe corresponde, preservando o que já existe.

Se a task já tiver uma linha citando o mockup só como referência externa (o caso da 3227), **substitua-a** pelo link do import datado — senão a spec fica com duas fontes visuais, uma delas inacessível ao Cursor.

## Guardrails

- **Nunca edite `platform/**`, `services/**` ou `infra/**`** — nem por shell (`sed`, `Set-Content`, redirecionamento). CLAUDE.md §2, sem exceção para "só um valor" ou "fix trivial". Achado nesses caminhos vira lista de correções para o Cursor.
- **Token do projeto vence o mockup** quando há equivalente (ADR-0011:61). O mockup vence só onde o projeto não tem resposta — e aí a decisão é do dev (layout é dele), não sua. Registre como **`dev (<seu nome>, <data>)`**; **`owner`** só com link para um comentário escrito pelo owner na WI ou na PR.
- **"O quê", não "como".** ADR-0039:14: a spec diz o quê e por quê; o como é do dev. Valor observável (`altura 56px`, `raio --shape-full`) entra. Técnica (qual mixin, qual seletor, qual classe criar) fica fora.
- **Rule `036`:** features não importam `@angular/material`; a API pública é `broker-*`. A seção nunca prescreve Material dentro de feature.
- **Toda afirmação de valor cita `arquivo:linha`** da fonte — mockup ou `_tokens.scss`. Valor sem procedência não entra na spec.
- **Não sincronize spec a partir do código** (CLAUDE.md §3). Ler o `.scss` do componente serve para *citar o token certo* e medir divergência; não para deixar o estado atual do código redefinir a intenção do design.

## Economia de contexto

O custo desta skill é dominado por leitura de mockup, não por raciocínio.

- Nunca `Read` integral de `styles.css` nem de `.jsx` — só Grep dirigido pelo recorte.
- `_tokens.scss` é lido uma vez, íntegro (110 ln é mais barato que três greps).
- `_palettes.scss` só quando um hex cru do core M3 precisa ser resolvido.
- **Sonnet basta**: o trabalho é grep e comparação de strings. Opus só se o recorte for redesenho estrutural, onde o julgamento é o produto.
- Uma task por sessão. Terminada a seção, `/clear` antes da próxima.

## Estado conhecido do design-system (confira antes de confiar)

Verdadeiro em 2026-09-11 — reconfira no `_tokens.scss` antes de usar como argumento:

- **Não existe escala de espaçamento.** Paddings e gaps são px soltos nos componentes. Todo espaçamento do mockup tende a cair no balde C.
- **Raio, tipografia, sombra e motion têm token:** `--shape-xs…full` (4/8/12/16/28/9999px), `--fs-xs…3xl` (11→28px), `--elev-0…3`, `--motion-*`.
- **`--broker-color-*` é citado em ~15 lugares mas nunca definido** — resolve sempre pelo fallback hardcoded. Se o mockup levar a um desses, é divergência preexistente do projeto: reporte, não conserte.
- **Componentes misturam token e literal.** O `broker-nav-item.component.scss` tem 22 `var(--)` e 13 hex literais — inclusive o badge "Em breve" em `#ffdfa1`, que é exatamente `--md-warning-container`.
