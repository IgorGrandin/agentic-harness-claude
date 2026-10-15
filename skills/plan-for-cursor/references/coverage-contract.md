# Contrato de cobertura e de fatias

Fonte única do contrato de cobertura de testes e do grafo de fatias. Quem
referencia: `plan-for-cursor` (dono), `plan-task`, `change-task` e `execute`.
Não copie este texto para outra skill; aponte para cá.

## 1. Grafo de fatias executável

Toda fatia de implementação registra:

- IDs das fatias pré-requisito, e cada dependência aponta para uma fatia real;
- um único dono de escrita e o write-set limitado (arquivos ou superfícies);
- os contratos compartilhados que consome ou produz. Contrato compartilhado é decidido antes de qualquer consumidor começar;
- os IDs dos critérios de aceite que ela entrega;
- os checks focados e o teste discriminante de cada fatia que carrega comportamento;
- se pode rodar em paralelo. Fatias paralelas não colidem em arquivo nem em estado mutável compartilhado.

Não divida só para aumentar a contagem de fatias. Marque explicitamente
qualquer premissa externa ou de runtime não verificada e nomeie a decisão que
bloqueia a execução.

## 2. Matriz de cobertura por critério de aceite

Antes de propor as fatias, monte a matriz:

| AC | Comportamento / cenário observável | Resultado esperado | Fronteira de produção | Teste ou check (existente ou planejado) | Discriminante |
|---|---|---|---|---|---|

- **Fronteira de produção:** o ponto do código que implementa o comportamento, com caminho quando verificado.
- **Discriminante:** o que falharia se o comportamento faltasse. Uma asserção que só observa um efeito vizinho não é evidência do comportamento alterado.
- Trace o fixture pelo ramo relevante até a fronteira de produção, ou delegue o fixture nomeando a propriedade e o que tem de falhar sem a mudança (passe 4 do `plan-for-cursor`). Não invente valores.

## 3. Dimensões de risco

Derive cenários das dimensões que se aplicam ao comportamento proposto:
fronteira e falha, concorrência, transação, retry e recuperação, autorização e
isolamento de tenant. Inclua as que se aplicam e diga por que as outras não se
aplicam.

Não exija teste por método, percentual de cobertura arbitrário, teste que só
espelha a implementação, nem rodada de mutação em massa. Use os menores checks
decisivos que as rules do projeto e o risco justificam.

## 4. Desafio independente da matriz

Antes de entregar o plano para execução, peça ao subagente `reviewer` (contexto
limpo, só leitura) que desafie a matriz contra a spec canônica e as fronteiras
de produção planejadas. A pergunta é: quais cenários faltam, quais asserções não
discriminam e quais riscos aplicáveis a matriz omite. O reviewer raciocina a
partir das invariantes de comportamento, e não apenas confirma que o teste
discriminante nomeado existe.

Resolva cada achado ou registre explicitamente por que não se aplica. Rode o
desafio uma vez para spec, baseline e matriz inalterados. Se algum deles mudar
depois, desafie só o delta de cobertura afetado.

## 5. Evidência vermelha

Identifique as invariantes críticas cujo teste pode mostrar vermelho com
segurança antes da implementação, ou por um check test-first estreito e
reversível dentro das rules do projeto. Registre o vermelho observado quando for
viável. Se chegar ao vermelho exigir mutação insegura, infraestrutura
indisponível ou técnica proibida pelo projeto, registre a limitação e use outro
check decisivo.
