# Registro de decisões

Fonte única de como as decisões de uma task são tomadas e registradas nas skills
do BrixBroker. Quem referencia: `plan-task` (dono), `spec-task`, `change-task`
e `execute`. Não copie este texto para outra skill; aponte para cá.

## Quem decide

O **dev**, o usuário que conversa com você, toma todas as decisões. Vocês as escolhem juntos: você traz as opções e a sua recomendação, e o dev escolhe.

Fato não é decisão: o que se responde lendo código, rules ou ADRs, você descobre sozinho. Pergunte uma decisão por vez, sempre com recomendação, na ordem da árvore de dependências (disciplina da skill `grilling`).

## Onde fica o registro

Todas as decisões da task ficam numa seção exclusiva **"Decisões do dev"** do Work Item. **O Work Item é a fonte de verdade e de consulta.** Isso é uma exceção ao ADR-0039, que trata o arquivo do repo como fonte para o resto da spec.

- **Espelho:** a mesma seção é copiada em `backlog/tasks/<id>-<slug>.md`, para a spec continuar idêntica nos dois lugares. Em divergência, vale o Work Item, e o espelho é corrigido.
- **Plano:** pode copiar as decisões que restringem quem executa, na seção "Decisões (não reabrir)", citando o ID e o Work Item. Em divergência, vale o Work Item, e o plano é corrigido.
- **Consulta:** antes de agir com base numa decisão (executar um plano, auditar, planejar um delta), leia a seção no próprio Work Item, pelo MCP `azure-devops` ou pelo fallback `az rest` do §1 do `plan-task`. Se o Work Item não puder ser lido, avise o dev e só use o espelho como substituto com a autorização dele.
- **Gravação:** gravar no Work Item é uma escrita externa. Grave em lote, por rodada, depois que o dev confirmar o texto. Atualize o espelho no mesmo passo, em commit próprio.

## Formato

Igual no Work Item e no espelho:

```markdown
## Decisões do dev
| ID | Resumo | Data |
|---|---|---|
| D1 | <uma frase que diga o que muda> | <data> |

### D1 — <título>
- **Problema:** o que acontece hoje e por que exige uma decisão. Explique os termos do domínio que aparecem (ex.: o que é um template "somente leitura").
- **Decisão:** o que muda, de forma concreta.
- **Motivo:** por que esta opção.
- **Alternativas descartadas:** uma linha cada, com o porquê. Omita quando não houve alternativa real.
- **Impacto e dependências:** o que a decisão afeta (outras WIs, contratos, testes) e os conflitos com outras decisões, inclusive os ainda não resolvidos.
- **Incertezas:** o que não foi confirmado, marcado como tal, e se a decisão depende disso. Escreva "nenhuma" quando não houver.
```

Regras:
- **A tabela é o índice;** o detalhe fica no bloco de cada decisão.
- **IDs são estáveis.** Uma decisão revista mantém o ID: atualize o bloco e acrescente ao Resumo "(revista em <data>)".
- **Cada decisão se explica sozinha.** Escreva para quem não viu a conversa nem o plano: explique os termos do domínio, não use apelidos criados na sessão e não remeta a "conforme discutido" ou "ver plano".
- **Releia antes de gravar.** Leia cada bloco como esse leitor. Se ele depender de um fato do plano, confira o fato no código ou na spec, para a decisão não herdar um erro do plano.
