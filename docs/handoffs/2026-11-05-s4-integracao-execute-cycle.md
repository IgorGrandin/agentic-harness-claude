# Handoff: S4, integração do plano de qualidade e custo

Para: sessão nova em **Sonnet 5.5 medium**, aberta em `C:\Users\igor.grandin\Documents\Projects\agentic-harness-claude`.
Plano (aprovado pelo owner em 2026-11-05): `docs/plans/execute-cycle-quality-cost.plan.md`, commit `4a57e04` na branch `feature/execute-cycle-quality-cost`. Leia §4 a §6, em especial a fatia S4.

## Onde estamos

As fatias S0 a S3 foram implementadas por subagentes, **sem commit**, cada uma num worktree:

| Fatia | Worktree (`.claude/worktrees/…`) | Base do worktree | Arquivos |
|---|---|---|---|
| S0 | `agent-aac6d34582976e866` | `4a57e04` | `scripts/report-wi-cost.ps1`, `tests/test-wi-cost.ps1`, `tests/fixtures/wi-cost/*` |
| S1 | `agent-a2a9c23959fc5ad69` | `2e12a6a` (sem o plano; nenhum arquivo em conflito) | `manifest.json`, `scripts/install.ps1`, `scripts/verify.ps1`, `hooks/precompact-handoff.ps1`, `tests/test-install.ps1`, `tests/test-precompact-handoff.ps1`, `benai-mods/plugins/handoff/hooks/register.tsx` e `register.test.tsx` |
| S2 | `agent-a4fc7e09f77098166` | `2e12a6a` | `skills/execute-ig/SKILL.md`, `skills/execute-ig/scripts/check-slice-commit.ps1`, `tests/test-slice-commit.ps1`, `tests/test-obligations-execute-ig.ps1`, `tests/fixtures/slice-commit/*` |
| S3 | `agent-a6d71b5d8e02df206` | `4a57e04` | `skills/execute-ig/scripts/check-plan.ps1`, `skills/plan-for-cursor/SKILL.md`, `skills/revise/SKILL.md`, `skills/review-pr/SKILL.md`, `tests/test-check-plan.ps1`, `tests/test-obligations-plans.ps1`, `tests/fixtures/check-plan/*` |

Conferido pela sessão anterior (2026-11-05): a lista de arquivos de cada worktree bate com o relato, e o teste próprio de cada fatia passa (`test-wi-cost`, `test-precompact-handoff`, `test-install`, `test-slice-commit`, `test-check-plan`). Os subagentes relataram `verify.ps1 -RunTests` verde em S1, S2 e S3, cada um isolado. A integração das quatro ainda não rodou.

## Próxima ação

Na branch `feature/execute-cycle-quality-cost` (checkout principal, árvore limpa), copie os arquivos de cada worktree, na ordem S0, S1, S2, S3, e faça **um commit por fatia**, com stage por caminho explícito. Os write-sets são disjuntos, então é cópia, sem merge. Depois siga o resto da S4 do plano.

## Pendências da integração (resolver antes do reviewer)

1. **S2: busca da fatia no `check-slice-commit.ps1`.** O script procura um título de nível 2 a 4 como "Fatia 1" e dá exit 2 se não achar. **HIPÓTESE:** os trailers `Execute-Slice` reais usam o ID do todo do frontmatter (`fatia-<slug>`). Teste contra um plano real do BrixBroker e os commits de fatia dele: `C:\Users\igor.grandin\Documents\Projects\brixbroker\.cursor\plans\wi_3691_b_motor_e_envios.plan.md` e `git -C ..\brixbroker log --grep "^Execute-Plan: .cursor/plans/wi_3691_b_motor_e_envios.plan.md$" --format=%H%n%B`. Se der exit 2, ajuste a busca para casar o ID do todo e acrescente um caso de teste com esse formato.
2. **S2: desvios a manter ou rejeitar.** O marcador `TODO` só casa em maiúsculas, porque "todo" é palavra comum em português. Os marcadores usam `\b`. Um commit sem nenhum trailer `Execute-*` é ignorado no modo `-Commit`. A recomendação é manter os três.
3. **S3: o `analise-ig:67` roda `check-plan.ps1` em plano ainda não commitado.** Esse plano agora precisa de `ADR/Rules` e de `Composição:`. Acrescente uma frase dizendo isso no `skills/analise-ig/SKILL.md`.
4. **S3: o `review-pr` §8 (perto da linha 140)** diz "Todo achado vira item de lista para o dev ou para o Cursor executar". Ajuste para não contradizer a convergência (só bloqueante, ou o que o dev mandar corrigir, vira item).
5. **S3: a exigência de `Composição:` é ruidosa.** Ela dispara com qualquer menção a `Integration` ou `HostSmoke` no corpo da fatia, inclusive numa nota de "delegado à 158". Aceitável por ora; registre como resíduo.
6. **S1: o AC5 não está verde.** O runner é `claude plugin test <dir do mod>`, com o `claude.exe` que não está no PATH, em `%LOCALAPPDATA%\Claude-Data\…\claude-code\<versão>\…\claude.exe`, e `CLAUDE_CONFIG_DIR` apontando para uma pasta temporária. A suíte do mod já falhava no Windows antes da mudança (0 de 10 no código intocado; o cache-clock e o reflect também falham). As asserções novas de limite (149.999, 150.000 e adiamento abaixo de 200k) rodam e foram vistas vermelhas. Reporte o AC5 como **parcialmente verificado**.
7. **S1: `sid` do mod × `session_id` do hook continua não verificado.** O cache-clock usa o mesmo `$.session.id()`, o que é consistente mas não prova. A S5 confere numa sessão real. Se for diferente, o fail-open limita o dano a um bloqueio desperdiçado.
8. **Plano, E2:** a WI 3691 tem 3 planos distintos no CSV, não 4 (o `plano_a` não está lá). Corrija o texto.
9. **`sync.ps1`:** rode-o. Se ele precisar conhecer a chave `hooks` do manifesto ou a pasta `hooks/`, ajuste-o (é do write-set da S4).

## Depois disso

- Rodar `scripts/verify.ps1 -RunTests` e `scripts/sync.ps1`.
- Atualizar o `README.md` e o status do plano.
- Um `reviewer` no diff `4a57e04..HEAD`, contra o plano. Depois o `verifier` no commit final.
- Não fazer push nem abrir PR sem o owner pedir. Não rodar `install.ps1` contra o `HOME` real: isso é a S5, do owner.
- Depois da integração, remover os quatro worktrees dos subagentes (`git worktree remove`), só com o OK do owner.

## Skills sugeridas

Nenhuma skill obrigatória. Siga o `CLAUDE.md` do repo (rótulos de evidência, um reviewer por entrega, verifier no gate).
