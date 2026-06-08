# Deployment Script Implementation Principles

This document defines the core principles and patterns for writing deployment scripts. Found in the `deploy/` directory where you work on these scripts.

## Script Numbering and Structure

### Principle: Numbered Scripts Follow Standard Objectives

**Rule**: Component deployments use numbered scripts (`01_*.ts`, `02_*.ts`, etc.) with standardized objectives.

**Numbering principles:**

1. **Script names describe what is done** - Filename indicates the action (e.g., `01_deploy.ts`, `02_upgrade.ts`, `03_configure.ts`)
2. **Avoid redundant naming** - Don't repeat information in number and name (use `01_deploy.ts`, not `01_deploy_contract.ts`)
3. **Final script is always 09_end.ts** - Standardized end state aggregate provides completion tag, intermediate steps (01-08) vary by component complexity

**Standard step objectives:**

- **01_deploy.ts** - Deploy proxy + implementation, initialize with deployer
  - Sync the contract being deployed (and any contracts it reads) immediately
    before acting via `syncComponentFromRegistry` /
    `syncComponentsFromRegistry`. The script factories
    (`createProxyDeployModule`, `createImplementationDeployModule`,
    `createUpgradeModule`, etc.) handle this automatically.
  - For a global pre-deploy reconciliation, use `npx hardhat deploy:sync`
    explicitly — it is no longer pulled in as an automatic dependency.
  - Each script should declare its own prerequisites explicitly, not rely on transitive dependencies
- **02_upgrade.ts** - Handle proxy upgrades via governance (generates TX batch)
- **04_configure.ts** - Deployer-only configure: role grants and params on contracts where the deployer is governor
- **05_transfer_governance.ts** - Revoke deployer GOVERNOR_ROLE; transfer ProxyAdmin to protocol governor
- **06_integrate.ts** (optional) - Wire the contract into the rest of the protocol
- **09_end.ts** - End state aggregate (only has dependencies and verification, no execution)
- **10_status.ts** - Read-only status display (see below)

The `03_*` slot is intentionally left empty so that `02_upgrade` can be inserted as a clearly distinct phase without renumbering. The `04_configure` numbering is the actual convention used throughout the tree.

### Principle: Status Scripts Are Read-Only

**Rule**: `10_status.ts` scripts MUST be purely read-only. They MUST NOT make on-chain changes, write transactions, or modify any state.

**Why**: When `--tags <scope>` is run without an action verb, only status scripts execute. Users rely on this for safe inspection of deployment state at any time — during planning, mid-deployment, and in production. Any mutation in a status script would violate this trust and could cause unintended state changes.

**How it works**:

1. Status scripts use `createStatusModule()`, which gates on `noTagsRequested()` — they only run when tags are present but no action verb is included
2. Stage scripts (01-08) use `shouldSkipAction(verb)` — they skip when their action verb is absent from `--tags`
3. Combined: `--tags GIP-0088` alone runs only `10_status.ts` (status reads on-chain directly and does not need a global sync first)

**Pattern**:

```typescript
// Component status — delegates to showDetailedComponentStatus (reads only)
export default createStatusModule(Contracts.issuance.IssuanceAllocator)

// Goal status — custom handler, must only use readContract/getCode
export default createStatusModule(GoalTags.GIP_0088, async (env) => {
  const client = graph.getPublicClient(env) as PublicClient
  // ✅ Read on-chain state and display
  const value = await client.readContract({ ... })
  env.showMessage(`  ${value ? '✓' : '✗'} check description`)
  // ❌ NEVER: execute(), tx(), deploy(), process.exit(1), TxBuilder
})
```

**Invariant**: If a script is named `10_status.ts`, it contains zero writes. No exceptions.

#### Example: RewardsEligibilityOracle (simple - 4 steps)

```
01_deploy.ts      - Deploy proxy + implementation
02_upgrade.ts     - Handle proxy upgrades (governance TX batch)
04_configure.ts   - Deployer-only configure (params, role grants)
09_end.ts         - End state aggregate
10_status.ts      - Read-only status display
```

#### Example: RewardsEligibilityOracle (full lifecycle)

```
01_deploy.ts                - Deploy proxy + implementation
02_upgrade.ts               - Handle proxy upgrades
04_configure.ts             - Configure params + role grants
05_transfer_governance.ts   - Revoke deployer role + transfer ProxyAdmin
06_integrate.ts             - Wire into RewardsManager (governance TX)
09_end.ts                   - End state aggregate
10_status.ts                - Read-only status display
```

**Note:** Step `03_*` is intentionally left empty so `02_upgrade` stays a clearly separate phase. Steps 04-08 are flexible and vary by component. Always use `09_end.ts` for the aggregate and `10_status.ts` for read-only status.

#### Tag structure in deployment-tags.ts

```typescript
// Component tags are PascalCase contract names matching the registry
ComponentTags = {
  REWARDS_ELIGIBILITY_A: 'RewardsEligibilityOracleA',
  // ...
}

// Action verbs are appended via --tags Component,verb
// e.g. --tags RewardsEligibilityOracleA,deploy
```

## Exit Codes and Flow Control

### Principle: Scripts Are Goal-Seeking, Not Sequential Steps

**Rule**: Each script checks its own preconditions and skips if not met. Scripts return (not exit) when work cannot proceed — subsequent scripts check their own state independently.

**Rationale**: Scripts run in sequence but must not assume a particular starting state. Each script is idempotent and goal-seeking: it checks on-chain state, does what's needed, and returns.

**Examples**:

```typescript
// CORRECT: Save governance TX and return (allows subsequent scripts to run)
saveGovernanceTx(env, builder, `ContractName activation`)
// Returns — subsequent scripts check their own preconditions

// CORRECT: Skip when precondition not met
if (!prerequisiteMet) {
  env.showMessage('  ○ Prerequisite not met — skipping')
  return
}

// CORRECT: Use shared precondition check to skip if done
const precondition = await checkIAConfigured(client, ia.address, rm.address)
if (precondition.done) {
  env.showMessage('✅ Already configured')
  return
}
```

### When to Use Exit Code 1

Use `process.exit(1)` only for:

- **Migration invariant violations** (data corruption risk, e.g. IA rate != RM rate before connection)
- **Verification failures** in `09_end` scripts
- **Sync failures** (can't proceed without address books)

Do NOT use `process.exit(1)` for:

- Governance TX generation (use `saveGovernanceTx` which returns)
- Preconditions not met (return/skip, let subsequent scripts check their own preconditions)
- Configuration already correct (idempotent check passed)
- Script successfully completed its work

### When to Throw Exceptions

Throw exceptions for:

- Unexpected errors (network failures, contract not found)
- Invalid configuration
- Programming errors
- Truly exceptional conditions

```typescript
// Exception for unexpected error
if (!deployer) {
  throw new Error('No deployer account configured')
}

// Clean exit for expected state
if (!upgraded) {
  env.showMessage('Prerequisite not met')
  process.exit(1)
}
```

## Idempotency

### Principle: All Deployment Steps Must Be Idempotent

**Rule**: Every deployment script MUST check current on-chain state and skip actions already completed.

**Pattern**:

```typescript
const func: DeployScriptModule = async (env) => {
  // 1. Check current state
  const checks = {
    configA: false,
    configB: false,
  }

  // Read on-chain state
  checks.configA = await readCurrentStateA()
  checks.configB = await readCurrentStateB()

  // 2. If all checks pass, exit early
  if (Object.values(checks).every(Boolean)) {
    env.showMessage('✅ Already configured\n')
    return
  }

  // 3. Execute only missing steps
  if (!checks.configA) {
    await executeConfigA()
  }
  if (!checks.configB) {
    await executeConfigB()
  }
}
```

## Import Patterns

### Principle: Use Package Imports for Shared Utilities

**Rule**: Import shared utilities from `@graphprotocol/deployment` package, not relative paths.

**Why**: Package imports are clearer, more maintainable, and work correctly with TypeScript path mapping.

**Pattern**:

```typescript
import type { DeployScriptModule } from '@rocketh/core/types'
import type { PublicClient } from 'viem'

// Deployment helpers (rocketh specific)
import { deploy, execute, read, tx, graph } from '@graphprotocol/deployment/rocketh/deploy.js'

// Contract utilities
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { requireContract, requireContracts } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'

// Governance utilities
import { getGovernor, getPauseGuardian } from '@graphprotocol/deployment/lib/controller-utils.js'
import { TxBuilder } from '@graphprotocol/deployment/lib/tx-builder.js'
import { getGovernanceTxDir } from '@graphprotocol/deployment/lib/execute-governance.js'

// Contract checks
import { requireRewardsManagerUpgraded } from '@graphprotocol/deployment/lib/contract-checks.js'

// ABIs
import { REWARDS_MANAGER_ABI, GRAPH_TOKEN_ABI } from '@graphprotocol/deployment/lib/abis.js'

// Tags
import { Tags, ComponentTags, actionTag } from '@graphprotocol/deployment/lib/deployment-tags.js'
```

**Anti-pattern** (don't do this):

```typescript
// ❌ Relative imports make code hard to move and unclear about package boundaries
import { Contracts } from '../../lib/contract-registry.js'
import { TxBuilder } from '../../lib/tx-builder.js'
```

## Shared Utilities

### Principle: Use Shared Functions for Common Patterns

**Rule**: Always use shared utilities instead of duplicating code.

### Deployer Pattern

```typescript
import { requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'

// ✅ GOOD: Use utility
const deployer = requireDeployer(env)

// ❌ BAD: Manual check repeated everywhere
const deployer = env.namedAccounts.deployer
if (!deployer) {
  throw new Error('No deployer account configured')
}
```

### Address Book Pattern

```typescript
// Get target chain ID (handles fork mode)
const targetChainId = graph.getTargetChainId()

// Get address books (fork-aware)
const horizonAddressBook = graph.getHorizonAddressBook(targetChainId)
const issuanceAddressBook = graph.getIssuanceAddressBook(targetChainId)

// Get contract from registry
const contract = requireContract(env, Contracts.RewardsManager)
```

### Viem Client Pattern

```typescript
// Get viem public client
const client = graph.getPublicClient(env) as PublicClient

// Read contract state
const value = (await client.readContract({
  address: contractAddress as `0x${string}`,
  abi: CONTRACT_ABI,
  functionName: 'someFunction',
  args: [arg1, arg2],
})) as ReturnType
```

## Governance Transaction Generation

### Principle: Standard Pattern for Governance TXs

**Pattern**:

```typescript
import {
  createGovernanceTxBuilder,
  executeTxBatchDirect,
  saveGovernanceTx,
} from '@graphprotocol/deployment/lib/execute-governance.js'
import { canSignAsGovernor } from '@graphprotocol/deployment/lib/controller-utils.js'

const { governor, canSign } = await canSignAsGovernor(env)

// Create TX builder (handles chainId, outputDir, template automatically)
const builder = await createGovernanceTxBuilder(env, `action-${contractName}`, {
  name: 'Human Readable Name',
  description: 'What this TX batch does',
})

// Add transactions
builder.addTx({ to: contractAddress, value: '0', data: encodedCalldata })
env.showMessage(`  + ContractName.functionName(args)`)

// Execute directly if possible, otherwise save for governance
if (canSign) {
  await executeTxBatchDirect(env, builder, governor)
} else {
  saveGovernanceTx(env, builder, `${contractName} activation`)
}
// Returns — does NOT exit. Subsequent scripts check their own preconditions.
```

### Metadata Standards

All governance TX batches should include descriptive metadata:

```typescript
meta: {
  name: 'Contract Upgrade',  // Short, human-readable title
  description: 'Upgrade ContractName proxy to new implementation',  // What it does
}
```

## Fork Mode Patterns

### Principle: Scripts Must Work in Both Fork and Production Modes

**Pattern**:

```typescript
// Use target chain ID (handles fork)
const targetChainId = graph.getTargetChainId()

// Use fork-aware address books
const addressBook = graph.getIssuanceAddressBook(targetChainId)

// Check if in fork mode (optional - for conditional behavior)
const isFork = graph.isForkMode()

// Governance TX directory is fork-aware
const outputDir = getGovernanceTxDir(env.name)
// Returns: fork/localhost/arbitrumOne/txs/ (fork)
//       or txs/arbitrumOne/ (production)
```

## Script Structure

### Standard Script Template

```typescript
import type { DeployScriptModule } from '@rocketh/core/types'
import type { PublicClient } from 'viem'

import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { Tags, ComponentTags } from '@graphprotocol/deployment/lib/deployment-tags.js'
import { requireContracts, requireDeployer } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'
import { graph } from '@graphprotocol/deployment/rocketh/deploy.js'

/**
 * Script purpose and description
 *
 * Details about what this script does.
 * Prerequisites if any.
 *
 * Usage:
 *   npx hardhat deploy --tags script-tag --network <network>
 */
const func: DeployScriptModule = async (env) => {
  // 1. Get named accounts
  const deployer = requireDeployer(env)

  // 2. Get required contracts
  const [contractA, contractB] = requireContracts(env, [Contracts.ContractA, Contracts.ContractB])

  // 3. Get viem client
  const client = graph.getPublicClient(env) as PublicClient

  // 4. Check prerequisites
  await requireSomePrerequisite(env)

  // 5. Show script header
  env.showMessage('\n========== Script Name ==========')
  env.showMessage(`Contract: ${contractA.address}\n`)

  // 6. Check current state (idempotency)
  const checks = {
    checkA: await checkStateA(),
    checkB: await checkStateB(),
  }

  if (Object.values(checks).every(Boolean)) {
    env.showMessage('✅ Already configured\n')
    return
  }

  // 7. Execute missing steps
  if (!checks.checkA) {
    await executeA()
  }

  // 8. Show completion
  env.showMessage('\n✅ Complete!\n')
}

// 9. Configure tags and dependencies
func.tags = Tags.scriptTag
func.dependencies = [ComponentTags.PREREQUISITE]

export default func
```

## Error Messages

### Principle: Clear, Actionable Error Messages with Dynamic Values

**Rule**: Use contract names from registry and tag constants - never hardcode them in messages.

**Why**: Hardcoded values break when contracts are renamed or tags change, and make code harder to maintain.

**Pattern**:

```typescript
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
// ✅ GOOD: Uses contract name from registry
const contract = Contracts.RewardsManager
env.showMessage(`\n❌ ${contract.name} has not been upgraded yet`)
env.showMessage(`   The on-chain ${contract.name} does not support IERC165/IIssuanceTarget`)
env.showMessage(`   Run: npx hardhat deploy:execute-governance --network ${env.name}`)
env.showMessage(`   (This will execute the pending ${contract.name} upgrade TX)\n`)

// ❌ BAD: Hardcoded contract name
env.showMessage(`\n❌ RewardsManager has not been upgraded yet`)
env.showMessage(`   Run: npx hardhat deploy:execute-governance --network ${env.name}`)

// ✅ GOOD: Shows what was found vs expected
env.showMessage(`  IA integrated: ${checks.iaIntegrated ? '✓' : '✗'} (current: ${currentIA})`)

// ❌ BAD: Vague error without context
env.showMessage('⚠️  Something is not ready')

// ❌ BAD: Just shows boolean without explanation
env.showMessage(`  IA integrated: ${checks.iaIntegrated}`)
```

## Contract Registry

### Principle: Use Contract Registry for Type Safety

**Pattern**:

```typescript
import { Contracts } from '@graphprotocol/deployment/lib/contract-registry.js'
import { requireContract } from '@graphprotocol/deployment/lib/issuance-deploy-utils.js'

// GOOD: Type-safe, refactorable, discoverable
const contract = requireContract(env, Contracts.RewardsManager)

// BAD: String literal (typos, hard to refactor)
const contract = requireContract(env, 'RewardsManager')

// Registry provides:
// - Type safety
// - Metadata (proxy type, address book, proxy admin)
// - Discoverability (IDE autocomplete)
```

## Documentation

### Principle: Every Script Has Clear Documentation

**Requirements**:

```typescript
/**
 * Brief description of what this script does
 *
 * Longer description with:
 * - Prerequisites
 * - What actions it performs
 * - Whether it's idempotent
 * - Whether it generates governance TXs
 *
 * Corresponds to: IssuanceAllocatorDeployment.md step X (if applicable)
 *
 * Usage:
 *   npx hardhat deploy --tags script-tag --network <network>
 *   FORK_NETWORK=arbitrumOne npx hardhat deploy --tags script-tag --network localhost
 */
```

### Principle: Deployment Documentation in docs/deploy/

**Rule**: Deployment documentation should be placed in `docs/deploy/`, mirroring the deploy script structure.

**Why not colocate?** The rocketh/hardhat-deploy script loader auto-loads all files in the `deploy/` directory. Placing `.md` files there causes loader errors. There's no extension filtering option available.

**Structure**:

```
deploy/                              docs/deploy/
  allocate/                            IssuanceAllocatorDeployment.md
    allocator/                         DirectAllocationDeployment.md
      01_deploy.ts                   rewards/
      02_upgrade.ts                    RewardsEligibilityOracleDeployment.md
      09_end.ts
  rewards/
    eligibility/
      01_deploy.ts
      02_upgrade.ts
      09_end.ts
```

**Cross-referencing**:

- Contract documentation (in `packages/issuance/contracts/`) should link to deployment documentation
- Deployment documentation should link back to contract documentation
- General framework documentation stays in `packages/deployment/docs/`

**Example references**:

```markdown
<!-- In contract doc: packages/issuance/contracts/allocate/IssuanceAllocator.md -->

For deployment instructions, see [IssuanceAllocatorDeployment.md](../../../deployment/docs/deploy/IssuanceAllocatorDeployment.md).

<!-- In deployment doc: packages/deployment/docs/deploy/IssuanceAllocatorDeployment.md -->

For contract architecture and technical details, see [IssuanceAllocator.md](../../../issuance/contracts/allocate/IssuanceAllocator.md).
```

**Rationale**: While colocation would be ideal, the deploy loader limitation requires this separation. The `docs/deploy/` structure mirrors deployment organization to maintain logical association.

## Testing

### Principle: Scripts Should Be Testable

**Pattern**:

```typescript
// Make scripts testable by:
// 1. Using shared utilities (mockable)
// 2. Checking state before executing
// 3. Being idempotent
// 4. Providing clear output

// Example test flow:
// 1. Run script first time -> executes actions
// 2. Run script second time -> skips (idempotent)
// 3. Check on-chain state matches expected
```

## Summary

### Key Principles Checklist

For every deployment script:

- [ ] Uses `return` (not `process.exit`) for precondition skips and governance TX saves
- [ ] Throws exceptions only for unexpected errors
- [ ] Is idempotent (checks state, skips if done)
- [ ] Uses package imports (`@graphprotocol/deployment`) not relative paths
- [ ] Uses shared utilities from `lib/`
- [ ] Uses `Contracts` registry for type safety and dynamic contract names
- [ ] Uses tag constants (never hardcodes tag strings)
- [ ] Works in both fork and production modes
- [ ] Has clear, actionable error messages with dynamic values
- [ ] Includes comprehensive documentation
- [ ] Follows standard script structure (01_deploy, 02_upgrade, ..., 09_end, 10_status)
- [ ] Properly configures tags and dependencies
- [ ] End state script is always `09_end.ts` with only dependencies
- [ ] `10_status.ts` is purely read-only (zero writes, zero TXs, zero exits)

### Anti-Patterns to Avoid

❌ Using `process.exit(1)` for precondition skips or governance TX saves (use `return`)
❌ Duplicating precondition checks instead of using shared functions from `lib/preconditions.ts`
❌ Duplicating code instead of using shared utilities
❌ Using relative imports (`../../lib/`) instead of package imports
❌ Using string literals instead of `Contracts` registry
❌ Hardcoding contract names in error messages (use `Contracts.X.name`)
❌ Hardcoding contract names in TX batch filenames (use `Contracts.X.name`)
❌ Hardcoding tag strings in messages (use tag constants)
❌ Hardcoding chain IDs instead of using `getTargetChainId()`
❌ Direct address book imports instead of `graph.get*AddressBook()`
❌ Vague error messages without actionable next steps
❌ Non-idempotent scripts that fail on re-run
❌ Using non-standard end script numbering (use `09_end.ts` always)
❌ Any mutation (write, TX, deploy, exit) in a `10_status.ts` script
