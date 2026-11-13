---
name: mockup-task
description: Gera o mockup das mudanças visuais de uma WI a partir da captura da tela real renderizada do app (DOM + todo o CSS aplicado), editando só a região que a WI muda com instâncias reais dos componentes broker-*, confere a fidelidade por pixel e entrega um único mockup (artefato do Claude, ou HTML local nos outros hosts) com as decisões D<n> verificáveis que a spec-frontend leva para a spec. Chamada pelo /plan-task quando a WI tem tela; também roda avulsa com "/mockup-task <WI>".
argument-hint: "nº do Work Item (ex.: 3990)"
---

# /mockup-task — mockup a partir da tela real

Repositório alvo: **Broker** (raiz do seu clone; caminhos relativos a ela).

## Por que esta skill existe

O mockup desenhado do zero (Claude Design) imita o app, mas não é o app: declara as próprias cores, não tem `broker-*` nem o CSS encapsulado do Angular e do Material. A reconciliação de tokens acerta os valores e os componentes, mas layout, hierarquia, larguras e shell saem de um desenho que nunca foi a tela real — e o executor reproduz o desenho, não o app (caso da 3990: cinco "divergências do mockup" na spec).

Aqui o mockup **parte da tela renderizada**: a captura é o app, e só a região que a WI muda é editada, com instâncias reais dos componentes. O resto da tela é conferido por pixel contra o app.

**O mockup é insumo aprovado, não fonte da verdade** (ADR-0011). A seta continua `spec → código`: o que o mockup decide sobe para a spec pela `spec-frontend`, e é a spec que o plano segue. O mockup não vai para o Git.

**O que esta skill não faz:** não escreve código de produto, não cria nem altera componente em `libs/`, não mexe no tema, no seed nem no realm, e **nada grava em `platform/**`** — nem `Write`/`Edit`, nem shell, nem o `--out`/`--saida` do script.

## Ferramentas

`$cap` daqui em diante é `node "$env:USERPROFILE/.claude/skills/mockup-task/scripts/capturar-tela.mjs"`. O script usa o Edge ou o Chrome instalados e instala `playwright-core`, `pngjs` e `pixelmatch` na primeira execução, fora do repo, em `%USERPROFILE%\.claude\brixbroker\captura\` (o `--data-dir` padrão; sessão de login fica ali também). Requer `node` no PATH.

| Comando | Para quê |
|---|---|
| `$cap auth --url <app> [--checar \| --sem-interativo]` / `--realm-json <realm> --usuario <user>` | sessão de login (credencial lida pelo script, nunca impressa; §3) |
| `$cap capturar --url <rota> --out <pasta> --nome "<nome>" --sem-interativo [--esperar <sel>] [--antes <passos.mjs>] [--viewport 390x844]` | HTML autossuficiente + `<nome>.referencia.png` |
| `$cap pecas --arquivo <html>` | componentes da tela (`broker-*`, `data-componente`, `data-novo`) com um seletor de cada |
| `$cap extrair --arquivo <html> --seletor <css> [--indice N]` | só o trecho |
| `$cap substituir --arquivo <html> --seletor <css> --com <frag.html> [--modo trocar\|antes\|depois\|dentro]` | aplica um fragmento |
| `$cap css-de --arquivo <doador.html> --para <html>` | traz o CSS de uma tela doadora |
| `$cap screenshot --arquivo <html> --out <png> [--recorte x,y,w,h]` | imagem do mockup (inteira ou recortada) |
| `$cap comparar --a <png> --b <png> --ignorar "x,y,w,h;…" --out <diff.png>` | percentual de pixels diferentes fora das regiões ignoradas |

**Nunca abra uma captura com `Read`.** Ela traz todo o CSS do app (centenas de KB) e fica no contexto pelo resto da sessão. No Claude, o hook `guarda-leitura` (mod `frontend-visual`) bloqueia; nos outros hosts, a regra é esta frase. Trabalhe só com `pecas`/`extrair`/`substituir`.

## Quem faz o quê

- **Trabalho mecânico (§3–§6):** subir/capturar, extrair e substituir, conferir, publicar. No Claude, despache um subagente (`Agent`, `subagent_type: "general-purpose"`, `model: "sonnet"`) com o id da WI, o resumo da WI já lido, o recorte e o modo (`montar` · `ajustar <pedido>` · `retomar`). Nos outros hosts, rode na própria thread.
- **O subagente não pergunta ao dev.** Toda dúvida vira uma pendência `P<n>` com opções e recomendação no `resumo.md` (§6). Pendência que bloqueia (estender × criar componente, valor fora dos tokens, estado não definido pela WI) → para no ponto mais adiantado e devolve `status: pendências`. A que não bloqueia → segue com a recomendação, marcada `provisório`.
- **Thread principal:** lê **só** o `resumo.md`, conduz o portão (§7) e a ida para a spec (§8). Nunca abre captura, PNG, fragmento ou HTML do mockup: o dev revisa o artefato.

## 1. A WI exige mudança visual? — e já existe mockup?

Mudança visual: descrição, critério ou comentário fala de tela, página, modal, botão, campo, coluna, filtro, card, mensagem exibida, layout ou responsividade; anexo é print ou wireframe; a área de impacto inclui `libs/features/**`, `libs/layout/**`, `libs/design-system/**` ou `apps/*/src/**` de UI. Sem sinal: devolva "sem mudança visual". Sinal fraco é pergunta ao dev (régua dos 95% do `/plan-task` §4).

Mockup existente: procure o link do artefato na §Especificação visual da spec, uma pasta `tmp/mockup/wi-<id>-*` e, para WIs antigas, um import em `platform/frontend/_imports/claude-design/` (só leitura). Achou: leia o `notes.md`, confira se cobre o pedido e complemente só o que faltar, republicando **o mesmo** artefato.

**Print anexado é referência, não gabarito.** Onde divergir do design system, o design system vence (item 12 da lista de bloqueios do owner), e a divergência vai para o dev ver.

## 2. Ler o design system na fonte

Só o que a tela precisa, a cada rodada — não copie para cá:

| O quê | Onde |
|---|---|
| Fronteira (Material só dentro dos `broker-*`), surfaces | ADR-0011 e ADR-0004 |
| Catálogo `broker-*`, inputs e variações reais | `platform/frontend/libs/design-system/README.md` e `libs/design-system/src/lib/` |
| Tokens | `libs/design-system/src/lib/theming/_tokens.scss` |
| Componentes de feature e de layout | `libs/features/<feature>/src/lib/components/**`, `libs/layout/**` |
| Rules de front-end | as da área, pelo mapa da `005` (`036`, `041`–`046`, `070`, `080`, `090`) |

## 3. Capturar a tela real — a base

Pasta de trabalho `<mockup>` = `tmp/mockup/wi-<id>-<slug>/<AAAA-MM-DD>/`. Antes de começar, confirme que está ignorada (`git check-ignore -q tmp/mockup/x`); se não estiver, pare e pergunte. Passos (`--antes`) e fragmentos ficam em `tmp/mockup/passos/` e `tmp/mockup/fragmentos/`, fora de `<mockup>`.

**Subir o app:** reaproveite o que responde (`broker-web` em `http://localhost:4201/`, `admin-web` em `http://localhost:4300/`; portas e comandos em `platform/frontend/README.md`). Senão, suba em background, com log em arquivo, o AppHost (`dotnet run --project src\Apps\Insurtech.AppHost`, em `platform/backend`) e `npx ng serve <app>` (em `platform/frontend`), e registre comando, PID, porta e log em `<mockup>/../servidores.md`. Derrube no fim só o que você subiu.

**Login — resolva antes de capturar, nunca na tela do Keycloak:**
1. `$cap auth --url <app> --checar` → `"valida": true` (exit 0): capture.
2. Inválida (exit 2): `$cap auth --url <app> --sem-interativo`. O script usa, nesta ordem, `HARNESS_LOGIN_USER`/`HARNESS_LOGIN_PASSWORD`, `--realm-json platform/backend/src/Apps/Insurtech.AppHost/keycloak/realms/<realm>.json --usuario <username>` (realm e usuário cujo perfil enxerga a tela: `corretoras-br` para o broker-web, `admin-produto-br` para o admin-web) e a credencial de teste que o dev salvou por origem em `~/.claude/brixbroker/captura/auth/credenciais-dev.json` (só app local).
3. Falhou (senha recusada, sem senha em texto no realm, Keycloak pediu troca de senha/OTP): escale ao dev com a mensagem do script; ele pode entrar uma vez pela janela (`$cap auth --url <app>`, sem `--sem-interativo`) ou salvar a credencial de teste no arquivo acima. Você nunca escreve a senha em arquivo, relatório, log ou prompt, nunca lê `credenciais-dev.json` e nunca cria usuário.

**Capturar** sempre com `--sem-interativo`:
- **Tela que a WI altera:** `$cap capturar --url <rota> --out "<mockup>/original" --nome "<Tela> - base" --sem-interativo`.
- **Estado** (aba, filtro, modal aberto): `--antes tmp/mockup/passos/<x>.mjs` com `export default async (page) => { … }`.
- **Responsiva:** capture de novo com `--viewport 390x844` e `--nome "<Tela> - base - estreita"` (e 768, se a rule da área pede).
- **Doadores:** componente que existe em **outra** tela (um `broker-select` `compact`, um `broker-dialog`) → capture essa tela (`--nome "doador - <componente>"`). É de lá que sai a marcação real.
- **Estados reais:** se o app chega ao estado (vazio por filtro sem resultado, erro de validação), capture em vez de desenhar.
- **Tela nova:** capture a tela **mais parecida** (mesmo shell, mesmo esqueleto de página) como base e esvazie a área de conteúdo. O shell e as peças continuam reais; o **arranjo** da região nova é montado — por isso só com containers do design-system (`broker-stack`, `broker-card`, a grade da página) e nenhum `gap`/`padding` inventado, e é o arranjo que o dev confere no portão e o `/verify-visual` confere pelos D<n>.
- O script devolve `faltando` (recursos que não baixou). Recurso faltando → anote como pendência; não ignore.

**O app não sobe ou a tela não é alcançável?** Pare e devolva `status: escalado`. Mockup sem captura só se o dev aceitar, marcado no `notes.md` e no cabeçalho do HTML: **"sem captura — fidelidade ao app não garantida"**.

## 4. Escolher as peças e editar a captura

Liste com `pecas` o que a tela já usa. Para cada elemento do pedido, nesta ordem:

1. **`broker-*` ou componente da feature que serve como está** → `extrair` uma instância real (desta captura ou de um doador), com os `_ngcontent-*`/`_nghost-*` intactos; troque só texto e estado no fragmento; aplique com `substituir`.
2. **Serve com variação que ele já suporta** (`density`, modificador) → só com instância real dessa variação capturada; senão capture uma tela que a tenha.
3. **Quase serve, mas exigiria mudar o componente** → pendência (estender × criar), com recomendação e as telas que consomem o componente.
4. **Nada serve** → componente novo dentro da feature, montado só com as variáveis `--md-*`/`--fs-*`/`--shape-*`/`--broker-space-*` que já estão no `:root` da captura, marcado como novo.

Nunca invente cor, fonte, espaçamento ou raio fora dos tokens. Valor que o tema não tem é pendência, não hex solto. Token novo não nasce nesta WI.

**Editar:**
- Copie `"<Tela> - base.html"` para `"<Tela> - Decisão.html"` pelo shell e mexa **só** na região que a WI muda (`extrair` → editar o fragmento → `substituir`).
- Peça de doador: `extrair` no doador e `css-de --arquivo <doador> --para <Decisão>` uma vez.
- Marque cada bloco, sem mudar layout: `data-componente="<broker-* ou caminho>"`, `data-variacao="…"`, `data-novo="<nome proposto>"`. É o que o plano e o `/verify-visual` leem.
- Anotações: com `substituir --seletor "body > script:last-of-type" --modo antes`, um botão fixo "mostrar anotações" (escondido por padrão) que contorna cada bloco com *reaproveitado: X* ou *novo: Y*. Nada além disso é injetado.
- **Um arquivo por estado:** `"<Tela> - Decisão.html"` (padrão), `"… - vazio.html"`, `"… - carregando.html"`, `"… - erro.html"`, e os de validação. Estado que a WI não definiu é pendência.
- **Dados:** troque os dados do seed por fictícios plausíveis, região por região, com o vocabulário canônico do `CLAUDE.md` do repo. Nada de dado real de cliente: o artefato é uma página hospedada.
- Cabeçalho em comentário HTML: WI, data, status (`rascunho` / `aprovado em <data>`), URL e data da captura.

**Conferir a fidelidade antes de mostrar:**

```
$cap screenshot --arquivo "<mockup>/original/<Tela> - Decisão.html" --out tmp/mockup/conferencia/decisao.png
$cap comparar --a "<mockup>/original/<Tela> - base.referencia.png" --b tmp/mockup/conferencia/decisao.png --ignorar "<x,y,w,h da região alterada>[;…]" --out tmp/mockup/conferencia/diff.png
```

`percentual` acima de **0,5%** fora da região ignorada = você alterou algo que a WI não pede (ou faltou recurso). Corrija e confira de novo; não apresente antes de passar. **Olhe pouco e recortado:** o percentual é o critério; para ver a região alterada, `screenshot --recorte`, e não releia a mesma imagem.

## 5. `notes.md` — as decisões verificáveis

Em `<mockup>/notes.md`, publicado junto:

```markdown
# WI <id> — <título curto>

Data: <AAAA-MM-DD> · Captura: <url> em <data>, <viewport> · Fidelidade fora da região: <percentual>
Artefato: <URL ou "local">

## Decisões
- **D1 — <elemento> → <opção>**: posição, tamanho em px, token (com o valor), tipografia, gap;
  estados e copy exata; acessibilidade (aria, foco). Motivo: <uma linha>.

## Colisões aceitas
- <o que pode truncar/quebrar e foi aceito>

## Peças
| Elemento | Reaproveitado (instância de onde veio) | Variação | Novo |

## Arquivos
- `original/<Tela> - Decisão.html` (padrão) · `original/<Tela> - Decisão - <estado>.html`
```

Cada decisão com **valor verificável** (px, token, copy, ordem). Decisão vaga não é verificável.

## 6. Publicar e devolver

**Claude:** publique com a ferramenta `Artifact` direto de `<mockup>`:
- `file_path` = `<mockup>/original/<Tela> - Decisão.html`; título `WI <id> — <Tela> (mockup)`;
- `files` (relativos à pasta `original/`): os outros estados, `assets/…`, `<Tela> - base.referencia.png` e `notes.md`;
- **não redesenhe:** a captura editada vence qualquer convenção de página de artefato (sem tema escuro, sem tokens do artefato, sem "melhorar"); se a ferramenta exigir, só um `<title>`;
- grave a URL em `<mockup>/artefato.txt` e no `notes.md`. Ajuste republica **o mesmo** artefato.
- O subagente sem a ferramenta `Artifact`: grave `status: publicar pela thread principal` e, no `resumo.md`, o `file_path` e o mapa `files` exatos.

**Outros hosts:** o mockup é o HTML local `<mockup>/original/<Tela> - Decisão.html`, que abre sozinho no navegador; se o host publica HTML navegável, use, sem redesenhar.

**`<mockup>/resumo.md`** — o único arquivo que a thread principal lê:

```markdown
# Mockup — WI <id>
status: pronto | sem mudança visual | pendências | publicar pela thread principal | escalado
artefato: <URL> | local
visual_local: tmp/mockup/wi-<id>-<slug>/<data>/original/<Tela> - Decisão.html
fidelidade: <percentual>

## Peças
| Elemento | Reaproveitado | Variação | Novo |
## Divergências (print × design system)
## Decisões fechadas
- D1 — <uma linha, com o valor verificável>
## Pendências
- P1 — <pergunta> · Opções: <a> | <b> · Recomendação: <a>, porque <motivo> · Decisão do dev: <em branco>
## Ajustes
## Servidores que subi
```

O subagente devolve uma linha: `resumo.md: <status> — <n> pendências, fidelidade <x>%, artefato <URL ou local>`.

## 7. Portão — trava o plano

A thread principal apresenta ao dev, curto: link do artefato (ou caminho local), fidelidade, tabela de peças, divergências e o que ainda é pergunta. Pendências: uma por vez, com recomendação ([registro de decisões](../plan-task/references/decisions.md)); a decisão vai para o `resumo.md` e o subagente retoma (`retomar`). Opções do portão: **Aprovar mockup** · **Ajustar** · **Cancelar**. Ajuste → subagente em `ajustar`, republica o mesmo artefato e volta ao portão.

**Sem aprovação, o `/plan-task` não grava o plano.**

## 8. Levar a decisão para a spec

Aprovado: marque `aprovado em <data>` no cabeçalho e no `notes.md` e aplique a skill `spec-frontend` com o `notes.md`, os blocos `data-novo` e a spec da task. **A spec carrega todos os valores verificáveis** — o mockup não está no Git, então nada que o plano ou a verificação visual cobrem pode existir só nele.

## 9. Devolver ao `/plan-task`

- `visual_reference:` = URL do artefato (ou `local`) e `visual_local:` = caminho do HTML da Decisão — vão para o frontmatter do plano e ligam o `/verify-visual`;
- componentes reaproveitados (com caminho e variação) e novos — as fatias de tela listam exatamente estes;
- decisões fechadas, uma linha cada — viram "Decisões (não reabrir)".

O mockup não tem commit. A spec alterada no §8 entra no commit de insumos do `/plan-task`.
