# packages/deployment - Claude Code Guidance

Parent: [../CLAUDE.md](../../CLAUDE.md)

## Required Reading

Before modifying any deployment scripts in `deploy/`, read:

- [ImplementationPrinciples.md](docs/deploy/ImplementationPrinciples.md) - Core patterns and rules for all deploy scripts

## Key Rules (from principles)

- **`saveGovernanceTx` returns** - governance TX generation returns (not exit), downstream scripts check their own preconditions
- **Idempotent scripts** - check on-chain state, skip if already done
- **Shared precondition checks** - use `lib/preconditions.ts` for configure/transfer checks, not inline copies
- **Package imports** - use `@graphprotocol/deployment/...` not relative paths
- **Contract registry** - use `Contracts.X` not string literals
- **Standard numbering** - `01_deploy`, `02_upgrade`, ..., `09_end`

## Additional Documentation

- [GovernanceWorkflow.md](docs/GovernanceWorkflow.md) - Governance TX generation and execution
- [LocalForkTesting.md](docs/LocalForkTesting.md) - Fork mode testing workflow
- [Architecture.md](docs/Architecture.md) - Package architecture
- [Design.md](docs/Design.md) - Design decisions
