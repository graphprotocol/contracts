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

- [Gip0088.md](docs/Gip0088.md) - GIP-0088 reference guide: scripts, tags, preconditions
- [Gip0088Runbook.md](docs/Gip0088Runbook.md) - GIP-0088 operational runbook: staged, gated execution plan
- [GovernanceWorkflow.md](docs/GovernanceWorkflow.md) - Governance TX generation and execution
- [LocalForkTesting.md](docs/LocalForkTesting.md) - Fork mode testing workflow
- [Architecture.md](docs/Architecture.md) - Package architecture
- [Design.md](docs/Design.md) - Design decisions
