# Hardhat-Deploy vs Ignition

## Summary

- **Recommendation:** Prefer `hardhat-deploy` for issuance deployments. It is simpler to operate, integrates naturally with Hardhat tasks and named accounts, produces first-class per-network deployment artifacts, and aligns with how `@graphprotocol/token-distribution` already ships deployments. Ignition’s declarative modules are powerful but add complexity for routine proxy deployments and multi-step governance orchestration we need here.
- **Approach:** Keep the current Ignition modules for reference, introduce `hardhat-deploy` alongside as an opt‑in path, and migrate incrementally. Reuse Toolshed address book utilities by adding a tiny adapter that mirrors `deployments/` state into the address book JSON.

## Evaluation Criteria

- **Reproducibility:** Resume/skip on rerun; deterministic ids; explicit artifacts per chain.
- **Proxy/Upgrades:** Atomic initialization, OZ Transparent/UUPS support, safe upgrades with clear diffs.
- **DX & Simplicity:** How easy it is to write/read/maintain deployment code; learning curve for contributors.
- **State & Outputs:** Where addresses end up; how they’re consumed by scripts/other packages.
- **Parameterization:** Per‑env configs, secrets, and multi‑network overrides.
- **Integration:** With Toolshed tasks, address-book, verification, CI.

## Comparison

- **Ignition**
  - Pros: Declarative dependency graph; built-in resume; clean module composition (`m.useModule`); strong tracing and future values; good for complex inter-module dependencies.
  - Cons: Proxy flows are more verbose; ergonomics for one-off executions (governance calls, scripted migrations) are less straightforward; output shape requires adapters to map into an address book; community examples and contributor familiarity are lower than `hardhat-deploy`.
- **hardhat-deploy**
  - Pros: Simple `deploy/NN_name.ts` files with `deployments.deploy` and `execute/read`; named accounts; tags and dependency ordering; fixtures for tests; native `deployments/` JSON per network; built-in proxy pattern (`proxy` options) and deterministic deploy; widely used and already in this repo (token-distribution).
  - Cons: Less “declarative graph” semantics; you manually orchestrate ordering via tags/deps; long, multi-actor sequences can sprawl if not structured.

## Issuance-Specific Considerations

- We deploy OZ Transparent proxies with atomic initialization; then accept ownership via governor. `hardhat-deploy` supports atomic init via `proxy: { execute: { init: ... } }` and/or `args`/`execute` steps.
- We need to track `proxy`, `implementation`, and `proxyAdmin` addresses. `hardhat-deploy` keeps all of these in `deployments/` (and exposes `deployments.save`). A tiny adapter can mirror into the address book JSON with the same shape Toolshed expects.
- Governance/ops tasks (sync pending impls, list status, upgrades) are simpler as Hardhat tasks that read `deployments` and the address book; we can reuse much of `packages/deploy/tasks/*`.

## How It Would Look (PoC sketch)

1) Add plugin to `@graphprotocol/issuance-deploy` (non-breaking, opt-in):
   - Add devDependency: `hardhat-deploy`.
   - Do NOT remove Ignition; keep both available while we compare.
2) Create `deploy/00_issuance.ts`:
   - Deploy `GraphIssuanceProxyAdmin`.
   - Deploy implementations for `IssuanceAllocator`, `PilotAllocation`, `RewardsEligibilityOracle`.
   - Deploy proxies with init data (atomic) pointing to the ProxyAdmin.
   - Post‑deploy: call `acceptOwnership` from the governor account (named account `governor`).
   - Save results: default `deployments` plus write-through to the address book.
3) Optional: `deploy/10_verify.ts` tag `verify` that runs `hardhat-verify` on impls and proxies.

Example core (abbreviated):

```ts
// packages/issuance/deploy/deploy/00_issuance.ts
import { DeployFunction } from 'hardhat-deploy/types'
import { ethers } from 'hardhat'

const func: DeployFunction = async (hre) => {
  const { deployments, getNamedAccounts } = hre
  const { deploy, execute } = deployments
  const { deployer, governor } = await getNamedAccounts()

  const pa = await deploy('GraphIssuanceProxyAdmin', {
    from: deployer,
    log: true,
  })

  const iaImpl = await deploy('IssuanceAllocator_Implementation', {
    contract: 'IssuanceAllocator',
    from: deployer,
    log: true,
    args: [process.env.GRAPH_TOKEN!],
  })

  const initData = (await ethers.getContractFactory('IssuanceAllocator')).interface.encodeFunctionData(
    'initialize',
    [governor],
  )

  const iaProxy = await deploy('IssuanceAllocator', {
    contract: 'TransparentUpgradeableProxy',
    from: deployer,
    log: true,
    args: [iaImpl.address, pa.address, initData],
  })

  if (iaProxy.newlyDeployed) {
    await execute('IssuanceAllocator', { from: governor, log: true }, 'acceptOwnership')
  }
}

func.tags = ['issuance', 'core']
export default func
```

Address book mirror (adapter idea):

```ts
// packages/issuance/deploy/scripts/save-address-book.ts (called after deploy)
import { promises as fs } from 'fs'
import path from 'path'

export async function saveToAddressBook(hre, file = 'addresses.json') {
  const { deployments, network } = hre
  const out = {} as any

  const pa = await deployments.getOrNull('GraphIssuanceProxyAdmin')
  const ia = await deployments.getOrNull('IssuanceAllocator')
  const iaImpl = await deployments.getOrNull('IssuanceAllocator_Implementation')

  if (ia) {
    out['IssuanceAllocator'] = {
      address: ia.address,
      implementation: iaImpl?.address,
      proxyAdmin: pa?.address,
      proxy: 'transparent',
    }
  }

  const target = path.resolve(process.cwd(), file)
  await fs.writeFile(target, JSON.stringify({ [network.config.chainId!]: out }, null, 2))
}
```

This mirrors the shape your current Ignition→address-book adapter writes, so downstream packages keep working.

## Migration Plan (Incremental)

- Phase 1: Add `hardhat-deploy` to `@graphprotocol/issuance-deploy`, create `deploy/00_issuance.ts`, wire named accounts (`deployer`, `governor`) in `hardhat.config.ts`, and add a `deploy` script. Keep Ignition intact for A/B.
- Phase 2: Add verification and governance helper tasks that rely on `deployments/` and the address book; ensure parity with existing tasks.
- Phase 3: CI job to run `hardhat deploy --tags issuance` on testnets, publish `deployments/` as artifacts, and commit the address book file when promoted.
- Phase 4: Remove Ignition modules once production parity is proven.

## Risk/Tradeoffs

- Contributors familiar with Ignition lose the declarative module graph; we mitigate with small, focused deploy files and consistent tags.
- Proxy/upgrade mistakes: use `hardhat-deploy`’s `deterministicDeployment`, tags, and dry-run on forks to catch diffs; keep a simple upgrade checklist task.

## Bottom Line

- For the issuance deployment’s needs (transparent proxies, atomic init, governance calls, address tracking, and repeatable ops), `hardhat-deploy` is the cleaner, lower‑friction option. It reduces bespoke adapters and aligns with existing monorepo practices (see `packages/token-distribution`). Retain Ignition until parity is validated, then remove to simplify the codebase.
