---
name: WI 2 fixture legado com a linha Rules antiga
---

## Manifesto de execução

- **SHA-base:** `{{SHA}}`

## Fatias

### Fatia 1 - Persistência

- Write-set: `platform/backend/src/M/Foo.cs`, testes em `platform/backend/tests/Insurtech.Integration.Tests/M/FooIntegrationTests.cs`.
- **Discriminante da fatia:** `FooIntegrationTests` caso X.

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
| Rules | abertas: `010`, `030` | mapa da `005` |
| **Cápsula** | ok | - |
| **Cobertura** | ok | - |
| **Reuso** | ok | - |
| Contradição | ok | - |
| **Erros declarados** | ok | - |
