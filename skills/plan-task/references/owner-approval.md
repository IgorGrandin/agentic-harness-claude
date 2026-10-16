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

   Contexto: <2-3 frases>
   Bloqueia: <o que não avança sem a resposta>

   | # | Decisão | Opções | Recomendação e porquê | Impacto |
   |---|---|---|---|---|
   ```

3. **Espere a resposta.** O usuário leva o pedido ao owner, numa conversa ou num PR, e volta com "aprovado", "rejeitado" ou "aprovado com ajuste", por item. Não grave artefato que dependa de uma decisão pendente.
4. **Registre** no artefato (seção "Decisões" do plano, spec ou delta) cada decisão com quem aprovou, quando e por qual canal. Exemplo: `aprovado pelo owner em 2026-10-16, via conversa relatada pelo usuário` ou `via PR #123`.

Uma decisão rejeitada ou alterada pode reabrir perguntas do usuário que dependiam dela. Volte ao passo 1 só para elas.
