---
name: WI 1 fixture com ADR/Rules e Composição
---

## Manifesto de execução

- **SHA-base:** `{{SHA}}`

## Fatias

### Fatia 1 - Persistência

- Write-set: `platform/backend/src/M/Foo.cs`, testes em `platform/backend/tests/Insurtech.Integration.Tests/M/FooIntegrationTests.cs`.
- **Discriminante da fatia:** `FooIntegrationTests` caso X.
- **Composição:** o host de produção registra `IFooRepository` em `platform/backend/src/Host/Program.cs`; o harness do teste sobe o mesmo `AddFoo()` e não registra o serviço à mão.

**Reuso:**
| Artefato do plano | Busca | Candidato | Decisão |
|---|---|---|---|
| `Foo` | `Foo` | nenhum | criar novo |

# Verificações feitas antes de entregar este plano

| Passe | O que verifiquei | Onde |
|---|---|---|
| **Manifesto** | ok | sha |
| Encanamento | ok | - |
| **Ambiente** | ok | - |
| Testes | ok | - |
| **Projeto do teste** | ok | - |
| Gate | ok | - |
| **ADR/Rules** | ADR-0060 D31: worker não compõe Crm; rules `010`, `030` abertas | mapa da `005` |
| **Cápsula** | ok | - |
| **Cobertura** | ok | - |
| **Reuso** | ok | - |
| Contradição | ok | - |
| **Erros declarados** | ok | - |
