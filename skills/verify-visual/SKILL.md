---
name: verify-visual
description: Confere no navegador se a tela implementada está fiel às decisões visuais da WI (estrutura, componentes broker-*, valores de token/px, copy e estados, em cada largura) e se o resto da tela não regrediu contra a captura base do mockup, produzindo achados V<N>-XX com evidência no formato do code review. Roda no passo 5 do /execute-ig quando o plano tem visual_reference; também avulsa com "/verify-visual <plano>".
argument-hint: "caminho do plano .cursor/plans/*.plan.md (opcional: rodada)"
---

# /verify-visual — a tela implementada contra o mockup aprovado

Automatiza a "conferência com o mockup aberto ao lado". Entra o plano; sai `visual-R<N>.md` com achados verificados no navegador.

**O que esta skill não faz:** não escreve nem corrige código (quem corrige é a sessão do `/execute-ig`), não roda testes nem o gate, não commita, não altera banco, seed ou realm para forçar um estado, não grava credencial em lugar nenhum.

`$cap` é `node "$env:USERPROFILE/.claude/skills/mockup-task/scripts/capturar-tela.mjs"` (skill `mockup-task`). Nunca abra uma captura com `Read`.

## 1. Entradas

- **Plano** — `visual_reference:` (URL do artefato ou `local`) e `visual_local:` (HTML da Decisão em `tmp/mockup/…/original/`). Sem `visual_reference`: devolva "sem verificação visual" e pare.
- **Gabarito**, nesta precedência: a §Especificação visual da spec (`backlog/tasks/<id>-<slug>.md`) → o `notes.md` do mockup → o HTML da Decisão. A spec é a fonte; o mockup é insumo.
- **Pasta do mockup** (`original/`, com os estados, `assets/` e `<Tela> - base.referencia.png`): o `visual_local`, se existe nesta máquina; senão, no Claude, baixe do artefato (`Artifact` `list` com `scope: "files"`, depois `read` com `paths` e `out_dir` = `tmp/pipeline/wi-<id>/visual/mockup/`); sem nenhum dos dois: veredicto **Escalado ao dev** — nunca reconstrua o mockup de memória.
- **Pasta de trabalho** `tmp/pipeline/wi-<id>/` e a **rodada** `N`, informadas pelo chamador (avulsa: rodada 1). Rodada `N > 1`: leia `visual-R<N-1>.md` para o de-para (§7).

## 2. Checklist antes de abrir o navegador

Uma linha por coisa verificável:

| Fonte | Vira item |
|---|---|
| Cada `D<n>` da spec | posição, ordem, tamanho (px), token (com o valor), tipografia, gap, copy exata, aria |
| Cada `data-componente` / `data-novo` do HTML da Decisão (`$cap pecas --arquivo "<Decisão>"`) | o bloco existe na tela, na mesma região, com o componente decidido |
| Cada estado do mockup (`… - Decisão - <estado>.html`) | padrão, vazio, carregando, erro, validação |
| Larguras | 1440×900 e as que a spec ou a rule da área pedem (768, 390/375) |

Para cada item, diga **como** verificar: estilo computado, presença no DOM, texto, ou comparação visual. Item que nenhuma fonte define com valor não é verificável — registre como tal, sem inventar gabarito. "Colisões aceitas" do `notes.md` não são achados.

## 3. Ambiente — reaproveitar antes de subir

1. **O app responde?** (`broker-web` `http://localhost:4201/`, `admin-web` `http://localhost:4300/`; portas e comandos em `platform/frontend/README.md`). Respondendo, use o que está de pé.
2. **Não responde:** suba em background, com log em `tmp/pipeline/wi-<id>/visual/logs/`, o AppHost e `npx ng serve <app>`; espere a porta e o build do Angular terminarem sem erro. Registre em `visual-servidores.md` só o que **você** subiu (comando, PID, porta, log). Nunca derrube servidor que você não subiu.
3. Ambiente que não sobe (Docker parado, porta ocupada, build quebrado) **não é achado de código**: veredicto **Escalado ao dev** com o trecho do log.

Subir servidor e abrir o navegador não é o gate do `/execute-ig` (invariante 1): nenhuma suíte roda aqui.

## 4. Login — sem a senha passar pelo modelo

A sessão é a do `capturar-tela.mjs`, salva fora do repo:

1. `$cap auth --url <app> --checar`; inválida → `$cap auth --url <app> --sem-interativo [--realm-json <realm do AppHost> --usuario <usuário de dev do perfil que vê a tela>]`, como na `mockup-task` §3. As fontes de credencial e a ordem estão lá. O script lê a senha e não a imprime.
2. **Claude (Playwright MCP do mod `frontend-visual`):** rode `$cap sessao-mcp --url <app>` **antes da primeira ferramenta do MCP**. Ele grava `mcp-storage-state.json` e `mcp-init.js`, que o MCP carrega ao abrir o navegador. Se o MCP já abriu o navegador nesta sessão, chame `browser_close` e navegue de novo. Erro do MCP sobre `storage-state` ou `init-script` é sinal de que o `sessao-mcp` não rodou: rode e chame `browser_close`. Os dois arquivos valem para um app por vez; ao trocar de app (`broker-web` ↔ `admin-web`), rode `sessao-mcp` de novo. Caiu na tela de login mesmo assim: escale — **não digite a senha pelo MCP**.
3. Nunca crie usuário, nunca use credencial real, nunca escreva a senha em relatório, log, arquivo ou prompt de outro agente.

## 5. Medir a tela implementada

**Claude — Playwright MCP é o motor.** Ferramentas `mcp__plugin_frontend-visual_playwright__*` (adiadas: carregue com ToolSearch `playwright`). O navegador é o Edge, headless, o mesmo da captura do mockup. Para cada largura × estado:
- `browser_resize` → `browser_navigate` na rota → chegue ao estado (`browser_click`, `browser_snapshot` para achar o alvo);
- **carregando / erro:** intercepte a chamada **dentro do navegador** (`browser_run_code_unsafe` com `page.route(...)` atrasando ou devolvendo 500 só para a rota da API daquela tela, só contra o app local). Não deu: o item fica **não verificado** — nunca altere código, banco ou API para provocar o estado;
- medições com `browser_evaluate`: `getComputedStyle` (largura, altura, `font-size`, `font-weight`, `color`, `gap`, `padding`), `querySelector` do componente dentro do contêiner certo, texto; tokens resolvidos com `getComputedStyle(document.documentElement).getPropertyValue('--md-…')`;
- `browser_take_screenshot` → `app-<estado>-<largura>.png` em `tmp/pipeline/wi-<id>/visual/`;
- olhe a imagem para alinhamento, sobreposição, truncamento e quebra de linha que nenhuma medição prevista pega. Pouco e recortado: cada imagem lida fica no contexto.

**Fallback sem MCP (Codex, Antigravity, ou MCP ausente):** o mesmo checklist pelo script, com a mesma sessão:
- medições: `$cap medir --url <rota> --itens <itens.json> [--antes <passos.mjs>] [--viewport <l>x<a>]`, com `itens.json` = `[{ "id": "D1", "seletor": "…", "props": ["width","font-size"], "vars": ["--md-primary"] }]`;
- imagem do app: `$cap capturar --url <rota> --out tmp/pipeline/wi-<id>/visual --nome "app-<estado>-<largura>" --sem-interativo [--antes …] [--viewport …]`;
- estados de erro/carregando: `page.route(...)` dentro do `--antes`.

**Mockup no mesmo enquadramento:** `$cap screenshot --arquivo "<pasta do mockup>/<Tela> - Decisão[ - <estado>].html" --out tmp/pipeline/wi-<id>/visual/mock-<estado>-<largura>.png --viewport <l>x<a>`.

## 6. Comparar e rotular

Dados fictícios do mockup nunca batem com os do app: **diferença de dado não é achado.** Compara-se:

- **Estrutura:** cada `data-componente` tem o componente correspondente na região certa, na ordem decidida.
- **Valores:** contra o `D<n>`, tolerância de 1px; cor normalizada em `rgb()`; token pelo valor resolvido.
- **Copy:** rótulos, títulos, mensagens de vazio e erro — texto exato da spec.
- **Fora da região que a WI muda**, a tela segue igual: `$cap comparar --a "<pasta do mockup>/<Tela> - base.referencia.png" --b <app-padrao-1440.png> --ignorar "<região alterada>" --out tmp/pipeline/wi-<id>/visual/diff-R<N>.png`. Diferença ali que não é dado é regressão.

Rotule cada item **`[visto]`** (observado no navegador, com evidência) ou **`[raciocinado]`**. **Achado só nasce de `[visto]`.**

## 7. Classificar

Mesmo esquema do code review, para a sessão do `/execute-ig` corrigir sem adaptar:

- **ID** `V<N>-<nn>`, eixo `Visual`.
- 🔴 **Bloqueante** — elemento ou estado ausente, componente diferente do decidido, copy errada, layout quebrado (sobreposição, overflow fora das colisões aceitas), regressão que quebra layout fora da região.
- 🟡 **Importante** — elemento certo com valor fora: px, token, gap, ordem, tipografia; regressão visual fora da região que não quebra layout.
- 🔵 **Sugestão** — diferença perceptível que nenhuma decisão cobre. Não vai para correção; fica para o dev.

Cada achado traz rota, largura, estado, seletor, **esperado × observado**, as capturas, o **arquivo provável** (pela fatia do plano) e a **correção esperada**, concreta.

Rodada `N > 1`: comece pelo de-para dos `V<N-1>-*` (✅ resolvido · ⚠️ parcial · ❌ não resolvido · 🔄 regressão). Parcial, não resolvido e regressão ganham ID novo.

## 8. Relatório — `tmp/pipeline/wi-<id>/visual-R<N>.md`

```markdown
# Verificação visual — Rodada <N>

- **Plano:** <caminho> · **visual_reference:** <URL | local> · **HEAD:** <sha>
- **App:** <app> em <url> · **Larguras:** <lista> · **Motor:** Playwright MCP | script (fallback)
- **Servidores:** reaproveitados | subidos por mim (ver visual-servidores.md)

## Status dos achados anteriores
<tabela — omitir na rodada 1>

## Achados desta rodada
### 🔴 Bloqueantes
- **V<N>-01** [Visual] `<arquivo provável>` — <rota · largura · estado> <descrição>. Esperado: <x>. Observado: <y> [visto]. Evidência: <capturas>. Correção esperada: <o que fazer>.
### 🟡 Importantes
### 🔵 Sugestões (não vão para correção)

## Não verificado
| Item | Motivo |

## Checklist
<N itens · N ok [visto] · N com achado · N não verificados>

## Veredicto
- [ ] ✅ **Aprovado** — nenhum 🔴 ou 🟡.
- [ ] 🔧 **Correção necessária** — <N> achado(s) 🔴/🟡.
- [ ] 🚨 **Escalado ao dev** — <ambiente, credencial ou decisão ambígua>.
```

Devolva ao chamador só o caminho, o veredicto e a contagem por severidade. As capturas por largura e estado são as que a rule da área pede anexar ao relatório da execução. "Não verificado" não reprova a rodada, mas chega ao dev no relatório final — nunca some.
