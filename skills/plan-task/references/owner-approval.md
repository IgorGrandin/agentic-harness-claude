# Contrato de aprovação do owner

Fonte única de quem decide o quê nas skills do BrixBroker. Quem referencia:
`plan-task` (dono), `spec-task` e `change-task`. Não copie este texto para outra
skill; aponte para cá.

## Quem é quem

- **Usuário:** o desenvolvedor que conversa com você. Responde às dúvidas de execução e leva os pedidos de aprovação ao owner.
- **Owner:** o gestor do projeto. É quem o `CLAUDE.md` do BrixBroker chama de "owner" ("Princípios inegociáveis salvo decisão explícita do owner"). Ele não conversa com você diretamente.

## O que é decisão do owner

- ADR novo ou emenda, e qualquer mudança estrutural.
- Escopo de release, congelamento (T93), corte ou aumento de escopo.
- Decisão de produto e mudança de contrato público.
- Custo fixo novo (T7).
- Mudança na spec canônica a partir do código ("sincronização reversa").
- Governança: rules, `CLAUDE.md`, settings e hooks do projeto, e exceção a regra do projeto.

## O que o usuário decide

- Dúvidas e lacunas da WI que não mudam escopo nem contrato.
- Desenho de testes, divisão e ordem de fatias, e abordagem de implementação dentro dos ADRs vigentes.
- Aceitar ou rejeitar achados de revisão e de auditoria.
- Redação do plano ou da spec, escolha do executor, commits e branches.

Fato não é decisão de ninguém: o que se responde lendo código, rules ou ADRs, você descobre sozinho. Quando a classe de uma decisão não estiver clara, pergunte ao usuário primeiro: "isso é seu ou do owner?". A palavra final sobre a classe é do usuário.

## Como conduzir

1. **Com o usuário:** as perguntas dele seguem a disciplina da skill `grilling`. Uma por vez, sempre com a sua recomendação, na ordem da árvore de dependências.
2. **Para o owner, em lote:** junte todas as decisões de classe owner da rodada num único pedido de aprovação, depois de esgotar as perguntas do usuário que não dependem delas. Monte o pedido assim:

   ```markdown
   # Pedido de aprovação — <WI/tema>

   Contexto: <2-3 frases para quem não conhece a task>
   Bloqueia: <o que não avança sem a resposta>

   | # | Decisão | Opções | Recomendação e porquê | Escolha do usuário | Impacto |
   |---|---|---|---|---|---|

   <um bloco por decisão, no formato de "Onde fica o registro" abaixo>
   ```

   O pedido segue a mesma regra do registro: cada item tem de se explicar sozinho para o owner, sem a conversa.

3. **Pré-aprovação do usuário (opcional).** O usuário pode escolher, para cada item, a opção que vai submeter ao owner. Com isso, você registra a decisão com a escolha dele e a marca de pendência, em vez de esperar.
4. **Submissão ao owner.** O usuário leva o pedido ao owner por um destes canais:
   - **Conversa:** ele volta com a resposta por item.
   - **PR em rascunho:** só quando o usuário pedir. O PR leva o espelho `backlog/tasks` (com a seção "Decisões") e o plano, quando houver, commitados, e a tabela de decisões pendentes na descrição. O owner aprova ou comenta no PR, e você consegue ler a aprovação e os comentários no Azure DevOps.
   - **Work Item:** um comentário com a tabela. O owner responde ali.

## Onde fica o registro (pedido do owner, 2026-10-16)

**Todas as decisões da task**, as do usuário e as de classe owner, ficam numa seção exclusiva **"Decisões"** do Work Item. **O Work Item é a fonte de verdade e de consulta dessa seção**, por decisão do owner. Isso é uma exceção ao ADR-0039, que trata o arquivo do repo como fonte para o resto da spec.

A mesma seção é copiada no arquivo espelho `backlog/tasks/<id>-<slug>.md` para manter a spec idêntica nos dois lugares. Em divergência, vale o Work Item, e o espelho é corrigido.

Formato, igual nos dois lugares:

```markdown
## Decisões
| ID | Resumo | Classe | Estado |
|---|---|---|---|
| D1 | <uma frase que diga o que muda> | usuário | decidido pelo usuário em <data> |
| D2 | <...> | owner | pré-aprovado pelo usuário em <data> — pendente do owner |

### D1 — <título>
- **Problema:** o que acontece hoje e por que exige uma decisão. Explique os termos do domínio que aparecem (ex.: o que é um template "somente leitura").
- **Decisão:** o que muda, de forma concreta.
- **Motivo:** por que esta opção.
- **Alternativas descartadas:** só para decisões de classe owner; uma linha cada, com o porquê.
- **Impacto e dependências:** o que a decisão afeta (outras WIs, contratos, testes) e os conflitos com outras decisões, inclusive conflitos que ainda não têm decisão.
- **Incertezas:** o que não foi confirmado, marcado como tal, e se a decisão depende disso. Escreva "nenhuma" quando não houver.
```

**Cada decisão tem de se explicar sozinha.** Escreva-a para um leitor que não viu a conversa nem o plano, como o owner lendo o Work Item ou outro dev semanas depois:
- explique os termos do domínio;
- não use apelidos internos nem nomes criados durante a sessão;
- não remeta a "conforme discutido" ou "ver plano".

A tabela é o índice, e o detalhe de cada decisão fica no bloco abaixo dela. Uma decisão revista mantém o ID e atualiza o bloco.

Antes de gravar, releia cada bloco como esse leitor e confirme que ele entende o problema, a decisão e o motivo sem abrir mais nada. Se o bloco depender de um fato do plano, confira o fato no código ou na spec. Assim a decisão não herda em silêncio um erro do plano.

O estado de uma decisão de classe owner é exatamente um destes:
- `pré-aprovado pelo usuário em <data> — pendente do owner`
- `aprovado pelo owner em <data>, via <canal>` (exemplos de canal: `conversa relatada pelo usuário`, `PR #123`, `comentário na WI #456`)
- `aprovado pelo owner com ajuste em <data>, via <canal>: <o ajuste>`
- `rejeitado pelo owner em <data>, via <canal>`

Os IDs (`D1`, `D2`…) são estáveis: uma decisão revista mantém o ID e troca o estado. Toda gravação no Work Item é uma escrita externa, feita só com a autorização do usuário, em lote por rodada. O espelho é atualizado em commit próprio, junto com a WI.

**O plano** pode conter as decisões e restrições que valem para quem executa, na seção "Decisões (não reabrir)", citando o ID (`D2`) e o Work Item. É uma cópia para a execução: em divergência, vale o Work Item, e o plano é corrigido. Decisão rejeitada não entra; decisão com ajuste entra já ajustada.

**Consulta.** Antes de decidir com base numa decisão registrada (executar um plano, auditar, planejar um delta), consulte a seção "Decisões" no próprio Work Item, pelo MCP `azure-devops` ou pelo fallback `az rest` do §1 do `plan-task`. Se o Work Item não puder ser lido, avise o usuário e só use o espelho como substituto com a autorização dele, deixando registrado que a consulta não foi ao Work Item.

**Pendência bloqueia execução.** Se a seção "Decisões" do Work Item tiver qualquer `pendente do owner`, o plano ligado à task não é executável: o `/execute` recusa. Spec com decisão pendente não é atribuída a um dev; ela pode existir no board, mas fica sem responsável até a aprovação.

Uma decisão rejeitada ou aprovada com ajuste pode reabrir perguntas do usuário que dependiam dela. Volte ao passo 1 só para elas e corrija a WI, o espelho e o plano.
