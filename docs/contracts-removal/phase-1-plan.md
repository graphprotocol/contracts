# Contracts Removal — Phase 1 (Frozen Moves and Tooling Cleanup) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move every frozen contract out of `packages/contracts` into graph-core or graph-token, with identical bytecode ignoring metadata. Simplify `legacy` and Ignition. RewardsManager, L2GNS, L2Curation and their storage contracts stay in `packages/contracts` until Phase P ports them.

**Architecture:**

- Moves run bottom-up, one PR per step: graph-core, graph-token, the frozen discovery contracts into graph-token, then EpochManager into graph-core. Each step removes a dependency on `packages/contracts`, so no cycle forms.
- Both packages keep the same subpaths under `contracts/`, so artifact paths and coverage-baseline keys don't change. They get their own Hardhat 2 config, and Foundry compiles their sources pinned to 0.7.6.
- Steps 5 and 6 don't move contracts. They remove `legacy`'s bytecode check, and Ignition's migrate flow, deployment records, verification tooling, migration-based test suites and 7.3.0 alias.

**Tech Stack:** pnpm workspaces, Hardhat 2, Foundry 1.8.3, solc 0.7.6 and 0.8.35, OpenZeppelin 3.4.2 and 5.4, Node 24.

**Spec:** `docs/contracts-removal/design.md` (§2, §3, §4, §5, "PR sequence → Phase 1").

**Revision 4:** P1 and P2 are done (#1394, #1395). The old P3 (#1396, everything into subgraph-discovery) is replaced; its `RewardsHook.t.sol` and `Multicall.t.sol` tests are kept. The old P4 (EpochManager into horizon) is replaced. The old P5 (RewardsManager into issuance) and P6 (Phase 2a) move to the Phase P plan, written when that phase starts. Counts marked `TBD` are filled in by a dry run before each task starts.

## Global Constraints

- Each task is a draft PR in one chain, the same way as Phase D: P1 targets `chore/contracts-removal-phase-0` (#1373), and each later task targets the one before. Nothing goes to main before the audit.
- Conventional commits, no Co-Authored-By line and no Claude attribution in commits or PRs.
- Moves use `git mv`. The only source edits allowed in moved `.sol` files are import paths, and Managed's pragma going from `^0.7.6` to `^0.7.6 || ^0.8.27`.
- 0.7.6 settings are exactly solc 0.7.6, optimizer enabled, 200 runs, no `evmVersion`, no `viaIR`, default metadata.
- Cross-package Solidity imports use `@graphprotocol/<package>/contracts/<subpath>`. Imports within a package stay relative.
- Until P6, `@graphprotocol/contracts-7.3.0` imports and `ignition/deployments/` don't change.
- RewardsManager, RewardsManagerStorage, MathUtils, L2GNS, L2GNSStorage, GNS, GNSStorage, L2Curation, CurationStorage and Multicall don't move in Phase 1.
- Issuance's code and tests never use horizon, subgraph-service or graph-token.
- No RPC URL or API key is ever written to a file, commit, report or PR. RPC URLs are passed only as inline env vars.
- `reference.json` and `coverage-baseline.json` are never regenerated. Only `manifest.json` paths change.
- Run `pnpm install --no-frozen-lockfile` right after any `package.json` edit, before the next build. The lockfile picks up unrelated patch bumps, so don't require an additive diff. Instead, check that it changes no solc, OpenZeppelin, Hardhat or forge-std version.

**Verification for every PR**, run from the repo root after committing. It doesn't replace CI's lint job (`lint.yml`):

```bash
pnpm install --frozen-lockfile
pnpm --filter @graphprotocol/contracts clean
pnpm -r --sequential run build
pnpm test:scripts
pnpm check:bytecode
pnpm -r --sequential run test:self
pnpm lint:sol; git status --short
git diff -M HEAD~1 -- 'packages/*/contracts/**/*.sol' | grep -E '^[-+]' | grep -vE '^(\+\+\+|---)|^[-+]\s*(import|pragma|\}? ?from)|^[-+]\s+\w+,?$'
FORK_NETWORK=arbitrumSepolia pnpm --filter @graphprotocol/deployment exec hardhat deploy --tags sync --skip-prompts --network fork
```

Expected:

- All exit 0 except the `grep` line. `check:bytecode` prints `OK: 21 contracts match` throughout Phase 1: the manifest already lists EpochManager and the moved discovery contracts, and only their paths change.
- `git status` prints nothing. `lint:sol`'s exit code only reflects its final `pnpm todo`, so `git status` is the real check that nothing was reformatted.
- The `grep` line prints nothing: moved and consumer contracts changed only in import and pragma lines. If it prints anything, the commit hook rewrote a file. The moved files pass prettier and solhint today, so this shouldn't happen. Stop and report rather than bypass the hook.
- From P5, `legacy`'s `test:self` runs only the source-hash check. From P6, the `deploy:protocol` CI job passes.

For the fork check, run the last command once on the parent commit and save its output to the scratchpad before starting the task. The two outputs must match. The public RPC default needs no secret, and a private one goes in as an inline `ARBITRUM_SEPOLIA_RPC=`. This check can't see a missing artifact, because `tryLoadArtifactFromSource` swallows the error, so P1 adds a registry test that can.

**Rebuild rule:** after a failed Hardhat compile in horizon or subgraph-service, run `rm -rf build cache` before retrying. `isProjectBuilt` passes on a partial build, and `loadTasks` then crashes on missing artifacts.

**TypeScript check:** `npx tsc --noEmit | grep TS2307`, in the named package, must print nothing. Plain `tsc` can't exit 0, because horizon and subgraph-service have unrelated errors today.

**Coverage gate** for P1 to P4, run in the moved package:

```bash
forge coverage --report lcov --report-file /tmp/<pkg>.lcov
node ../../scripts/contracts-migration/summarize-coverage.mjs /tmp/<pkg>.lcov /tmp/<pkg>.json
node ../../scripts/contracts-migration/compare-coverage.mjs ../../scripts/contracts-migration/coverage-baseline.json /tmp/<pkg>.json <moved contract paths>
```

solidity-coverage and forge count lines differently (Multicall is 6/8 in the baseline and 6/9 in forge with the same 6 hits), so line percentages can't be gated directly. The gate fails if a function hit in the baseline isn't hit now. It also prints each file whose line percentage is below baseline. List those files in the PR with a reason, or add a test. Never lower the baseline.

## Review Focus

1. **A test runs different code from what deploys.** Foundry compiles dual-pragma contracts as 0.8.35 with the optimizer off unless pinned, and they would still pass. P1 to P4 each have a test that Foundry's bytecode equals the Hardhat artifact's, ignoring metadata.
2. **The commit hook rewrites moved files.** lint-staged runs on renamed `.sol` files, and comment or formatting edits don't change bytecode, so `check:bytecode` can't see them. The `grep` line in the verification block catches this.
3. **A package loads only when a command runs.** `require.resolve` in `packages/deployment` can pass `build`. P1's registry test and the TypeScript check cover it.
4. **Something outside the deleted files still uses them.** P6 deletes tasks, scripts, configs and suites that docs, other tasks or local-network might reference. P6 Step 2 lists every user before deleting.

---

### Task P1: Move the governance and proxy contracts to graph-core

Done: #1394.

**Files:**

- Move: from `packages/contracts/contracts/` to `packages/graph-core/contracts/`, same subpaths: `governance/{Controller,Governed,Managed,Pausable}.sol`, `upgrades/{GraphProxy,GraphProxyAdmin,GraphProxyStorage,GraphUpgradeable}.sol`, `tests/{GovernedMock,ManagedMock}.sol`
- Create: `packages/graph-core/hardhat.config.ts`, `README.md`, `.solhint.json` and `prettier.config.cjs` (the last two copied from `packages/contracts`), `.changeset/graph-core-initial.md` (`major`)
- Modify: `packages/graph-core/package.json`, `foundry.toml`, its tests
- Modify: remaining `packages/contracts/contracts/**` imports and `packages/contracts/package.json`
- Modify: horizon `contracts/staking/HorizonStakingBase.sol`, `test/unit/GraphBase.t.sol`, `test/unit/escrow/constructor.t.sol`; subgraph-service `test/unit/SubgraphBaseTest.t.sol`; testing `test/harness/{FullStackHarness,RealRewardsHarness}.t.sol`
- Modify: `ProtocolFixture.t.sol` and `foundry.toml` `fs_permissions` in graph-token, subgraph-discovery, horizon and issuance
- Modify: `package.json` of graph-token, subgraph-discovery, issuance, horizon, subgraph-service, testing, deployment
- Modify: `packages/deployment/lib/{artifact-loaders,contract-registry,deploy-implementation,deployment-validation}.ts`, `scripts/generate-abis.ts`, `tasks/verify-contract.ts`, `test/bytecode-comparison.test.ts`
- Modify: `scripts/contracts-migration/manifest.json`, `.github/workflows/publish.yml`, `.gitignore`, `pnpm-lock.yaml`
- Create: `scripts/contracts-migration/compare-coverage.mjs`, `compare-coverage.test.mjs`, `packages/deployment/test/registry-artifacts.test.ts`

**Interfaces:**

- Consumes: nothing.
- Produces:
  - `@graphprotocol/graph-core/contracts/...` and `@graphprotocol/graph-core/artifacts/...`.
  - `ProtocolFixture._deployPkg(string memory id, bytes memory args) returns (address)`, wrapping `deployCode` and honouring an active prank. `id` has the form `"Controller.sol:Controller"`. `_deployArtifact` stays for Hardhat JSON. Each package has its own copy of `ProtocolFixture`, so P2 and P3 add the same helper.
  - `ArtifactSource` members `{ type: 'graph-core' | 'graph-token' | 'subgraph-discovery'; path: string; name: string }`, all served by `loadPackageArtifact(pkg, path, name)`.
  - `compareCoverage(baseline, current, files)` returning `{ regressions, belowLines }`.

**New package setup**, also used by P2 and P3:

- `files` of contracts, artifacts, types and README; `exports` of `./artifacts/*`, `./contracts/*`, `./types` and `./types/*`; version `0.0.0` (the `major` changeset takes it to 1.0.0); no `"private"` and no `"type": "module"`.
- Scripts: `build` is `pnpm build:dep && pnpm build:self`, `build:self` is `hardhat compile --quiet`, `prepack` is `pnpm build` (`publish.yml` has no build step, and artifacts and types are gitignored), `clean` is `rm -rf artifacts/ cache/ types/ forge-artifacts/ cache_forge/ coverage/`, and `lint:sol` matches `packages/contracts`.
- dependencies: `@graphprotocol/interfaces`, because the published sources import it.
- devDependencies: `hardhat`, `hardhat-ignore-warnings`, `@nomicfoundation/hardhat-verify` 2.1.1, `@typechain/hardhat`, `@typechain/ethers-v5`, `typechain`, `ethers ^5.7.2`, `@ethersproject/{abi,bytes,providers}`, `ts-node`, `typescript`, `solhint`, `prettier`, `prettier-plugin-solidity`, `forge-std`, each at the version `packages/contracts` uses. Remove `@graphprotocol/contracts`.
- Add `packages/<pkg>/types/` to root `.gitignore`.
- `hardhat.config.ts` has the exact 0.7.6 settings, the Arbitrum networks, `etherscan`, `typechain` (target `ethers-v5`, outDir `types`) and `warnings` from `packages/contracts/hardhat.config.ts`.

graph-core also has `@openzeppelin/contracts ^5.4.0`.

- [ ] **Step 1: Write `compare-coverage` tests first.** Test: a baseline function missing from `current`'s `functionsHit`, comparing after stripping a `Contract.` prefix, is a regression; a named file absent from `current` is a regression unless its baseline `linesFound` is 0; a file absent from the baseline throws; a line percentage below baseline appears in `belowLines` and isn't a regression. Run `pnpm test:scripts`. Expected: FAIL.
- [ ] **Step 2: Implement `compare-coverage.mjs`** with a CLI of `<baseline.json> <current.json> <file...>` that prints both lists and exits 1 only on regressions. Run `pnpm test:scripts`. Expected: PASS.
- [ ] **Step 3: Record the fork output on the parent commit** as the verification block says.
- [ ] **Step 4: Make the move.** `git mv` the files, change Managed's pragma, and rewrite imports of these files in `packages/contracts` to `@graphprotocol/graph-core/contracts/...`. Add `@graphprotocol/graph-core` as a devDependency of contracts, horizon, subgraph-service, testing, graph-token, subgraph-discovery and issuance, and as a dependency of deployment. Apply the package setup, then install.
- [ ] **Step 5: Build the package.** Run `pnpm --filter @graphprotocol/graph-core build:self`. Expected: compiles 27 files.
- [ ] **Step 6: Set the graph-core Foundry config.** Set `src = 'contracts'`, remove `solc_version`, add the remapping `@openzeppelin/=node_modules/@openzeppelin/`, and add:

  ```toml
  optimizer = true
  optimizer_runs = 200
  compilation_restrictions = [
      { paths = "contracts/**", version = "=0.7.6" },
      { paths = "test/**", version = "=0.8.35" },
  ]
  fs_permissions = [{ access = "read", path = "artifacts" }]
  ```

- [ ] **Step 7: Switch graph-core's tests to `deployCode`.** Add `_deployPkg`, and replace `CORE_ARTIFACTS`/`PKG_ARTIFACTS` uses with ids such as `"Controller.sol:Controller"`, `"GovernedMock.sol:GovernedMock"`. Remove the constants. Rewrite `test_Fixture_ArtifactReadable` and `test_Fixture_RevertWhen_ArtifactMissing` around `vm.getCode`, keeping the external wrapper, because `vm.expectRevert` needs the call one level down.
- [ ] **Step 8: Pin Review Focus 1.** Add `test_Fixture_FoundryControllerMatchesHardhat`: `vm.getCode("Controller.sol:Controller")` equals `.bytecode` in `artifacts/contracts/governance/Controller.sol/Controller.json`, each with the CBOR metadata tail stripped using its final two length bytes. `forge coverage` compiles with the optimizer off, so the test starts with `vm.skip(vm.isContext(VmSafe.ForgeContext.Coverage))`.
- [ ] **Step 9: Cover `GraphProxy.receive()`.** Baseline coverage hit it and the port doesn't. Add a test sending ETH to a proxy, with the expected result read from `GraphProxy.sol:65-66`. Run `pnpm --filter @graphprotocol/graph-core test:self`. Expected: 51 passing or more, 0 failing.
- [ ] **Step 10: Repoint other packages' fixtures.** In graph-token, subgraph-discovery, horizon and issuance, set `CORE_ARTIFACTS` to `node_modules/@graphprotocol/graph-core/artifacts/contracts/` and add that path to `fs_permissions`. `PKG_ARTIFACTS` stays on `packages/contracts` for now. Rewrite the horizon, subgraph-service and testing imports to graph-core.
- [ ] **Step 11: Generalize the deployment loader.** Add `loadPackageArtifact`, the new `ArtifactSource` members, and the `getLibraryResolver`, `getPackageDir` and `getFullyQualifiedContractName` cases. Keep `type: 'contracts'` and `loadContractsArtifact` working. Change no registry entry yet: none of them point at graph-core. Update `manifest.json` for Controller, GraphProxy, GraphProxyAdmin.
- [ ] **Step 12: Pin Review Focus 5.** Add `test/registry-artifacts.test.ts`, calling the throwing `loadArtifactFromSource` for every entry in `CONTRACT_REGISTRY` that has an `artifact`, and asserting non-empty bytecode. Make the `before` hook at `bytecode-comparison.test.ts:172-188` throw instead of skipping when the import fails. Run `pnpm --filter @graphprotocol/deployment test:self`. Expected: PASS.
- [ ] **Step 13: Add `graph-core` to the `publish.yml` options,** and check the lockfile.
- [ ] **Step 14: Commit.** `refactor(graph-core): move governance and proxy contracts`
- [ ] **Step 15: Run the verification block and the coverage gate** for `contracts/governance/*.sol` and `contracts/upgrades/*.sol`.

---

### Task P2: Move the token and bridge contracts to graph-token

Done: #1395.

**Files:**

- Move: `token/GraphToken.sol`, `l2/token/{L2GraphToken,GraphTokenUpgradeable}.sol`, `utils/TokenUtils.sol`, `gateway/{GraphTokenGateway,L1GraphTokenGateway,BridgeEscrow}.sol`, `l2/gateway/L2GraphTokenGateway.sol`, `arbitrum/{L1ArbitrumMessenger,L2ArbitrumMessenger,AddressAliasHelper}.sol`, `arbitrum/{Arbitrum,README}.md`, `tests/{CallhookReceiverMock,TokenUtilsMock}.sol`, `tests/arbitrum/{BridgeMock,InboxMock,OutboxMock}.sol`
- Create: `packages/graph-token/hardhat.config.ts`, `README.md`, `.solhint.json`, `prettier.config.cjs`, `.changeset/graph-token-initial.md` (`major`)
- Modify: `packages/graph-token/{package.json,foundry.toml}` and tests
- Modify: remaining `packages/contracts/contracts/**` imports, `packages/contracts/package.json`
- Modify: horizon `contracts/payments/{GraphPayments,PaymentsEscrow}.sol`, `contracts/staking/HorizonStaking.sol`; subgraph-service `contracts/{DisputeManager,SubgraphService}.sol`, `contracts/libraries/AllocationHandler.sol`, `contracts/utilities/AllocationManager.sol`
- Modify: `packages/subgraph-discovery/test/unit/shared/DiscoveryTest.t.sol`, `foundry.toml`, `package.json`
- Modify: `package.json` of horizon, subgraph-service, testing, deployment
- Modify: `packages/deployment/lib/contract-registry.ts` (L2GraphToken), `test/bytecode-comparison.test.ts:239`
- Modify: `manifest.json`, `publish.yml`, `.gitignore`, `pnpm-lock.yaml`

**Interfaces:**

- Consumes: `@graphprotocol/graph-core/contracts/...`, the same `_deployPkg` helper, `{ type: 'graph-token' }`, `compare-coverage.mjs`, the new package setup.
- Produces: `@graphprotocol/graph-token/contracts/utils/TokenUtils.sol` and `@graphprotocol/graph-token/artifacts/...`; `TOKEN_ARTIFACTS` in `DiscoveryTest.t.sol`.

Package setup follows P1, plus `@openzeppelin/contracts` and `contracts-upgradeable` at exactly 3.4.2, `arbos-precompiles ^1.0.2`, and `@graphprotocol/graph-core` as a dependency. Foundry config follows P1 Step 6, plus the remapping `arbos-precompiles/=node_modules/arbos-precompiles/` and `fs_permissions` for graph-core's artifacts. Fixtures keep reading `CORE_ARTIFACTS` as Hardhat JSON, because forge doesn't compile Controller here. Tests still can't import IGraphToken and keep their local `Like` interfaces.

The README states that GraphToken, L1GraphTokenGateway and BridgeEscrow here aren't the code running on mainnet, which `packages/legacy` holds.

- [ ] **Step 1: Make the move** and rewrite imports, including `packages/contracts`' remaining uses of TokenUtils. Rewrite the seven 0.8 importers to `@graphprotocol/graph-token/contracts/utils/TokenUtils.sol`. Add `@graphprotocol/graph-token` as a devDependency of contracts, horizon, subgraph-service, testing and subgraph-discovery, and as a dependency of deployment. `testing` needs it because horizon's sources are compiled through its remappings. Install.
- [ ] **Step 2: Build the package.** Run `pnpm --filter @graphprotocol/graph-token build:self`. Expected: exit 0.
- [ ] **Step 3: Switch `PKG_ARTIFACTS` to `_deployPkg` ids** in `test/unit/**`, adding the helper and keeping `CORE_ARTIFACTS`. Add the Review Focus 1 test for L2GraphToken, reading graph-token's own Hardhat artifact. Run `pnpm --filter @graphprotocol/graph-token test:self`. Expected: 125 passing, 0 failing.
- [ ] **Step 4: Add `TOKEN_ARTIFACTS` to `DiscoveryTest.t.sol`**, pointing at `node_modules/@graphprotocol/graph-token/artifacts/contracts/`, with its `fs_permissions` entry, and load L2GraphToken from it. Run `pnpm --filter @graphprotocol/subgraph-discovery test:self`. Expected: 82 passing.
- [ ] **Step 5: Update deployment.** Set the L2GraphToken registry entry to `{ type: 'graph-token', path: 'l2/token', name: 'L2GraphToken' }`. In `bytecode-comparison.test.ts`, load L2GraphToken through `loadPackageArtifact`. Update `manifest.json` for GraphToken, L2GraphToken, L1GraphTokenGateway, L2GraphTokenGateway and BridgeEscrow.
- [ ] **Step 6: Add `graph-token` to `publish.yml`,** and check the lockfile.
- [ ] **Step 7: Commit.** `refactor(graph-token): move token and bridge contracts`
- [ ] **Step 8: Run the verification block and the coverage gate** for the moved contracts, excluding `contracts/arbitrum/*`, which the baseline doesn't list, and mocks. Expected: `packages/testing` reports 24 passing with 0 skipped.

---

### Task P3: Move the frozen discovery contracts to graph-token

**Files:**

- Move: from `packages/contracts/contracts/` to `packages/graph-token/contracts/`, same subpaths: `discovery/{SubgraphNFT,SubgraphNFTDescriptor}.sol`, `curation/GraphCurationToken.sol`, `libraries/{Base58Encoder,HexStrings}.sol`
- Modify: `packages/subgraph-discovery/test/unit/shared/DiscoveryTest.t.sol` (load the moved contracts from `TOKEN_ARTIFACTS`)
- Create: `packages/subgraph-discovery/test/unit/**/{RewardsHook,Multicall}.t.sol`, taken from #1396
- Modify: `packages/horizon/addresses.json`, `packages/address-book/src/horizon/addresses.json`; create `.changeset/horizon-curation-addresses.md` (`@graphprotocol/address-book: minor`)
- Modify: `packages/deployment/lib/{artifact-loaders,contract-registry,deploy-implementation,deployment-validation}.ts`, `scripts/generate-abis.ts`, `tasks/verify-contract.ts` (remove the `subgraph-discovery` cases P1 added)
- Modify: `scripts/contracts-migration/manifest.json` (paths of SubgraphNFT, SubgraphNFTDescriptor and GraphCurationToken)
- Create: graph-token tests under `test/unit/discovery/` and `test/unit/curation/`, only for baseline functions not hit otherwise (see Step 4)

**Interfaces:**

- Consumes: graph-token's package setup and `_deployPkg` from P2.
- Produces: `@graphprotocol/graph-token/artifacts/contracts/{discovery,curation}/...`.

No Ignition change: the modules read these three artifacts from the 7.3.0 alias until P6.

- [ ] **Step 1: Record the fork output on the parent commit.**
- [ ] **Step 2: Make the move.** `git mv` the five files. Their imports are Governed (already graph-core), OpenZeppelin 3.4.2, `@graphprotocol/interfaces` and each other (relative, unchanged), all available in graph-token. Expected: `git grep -nE "(SubgraphNFT|GraphCurationToken|SubgraphNFTDescriptor|HexStrings|Base58Encoder)\.sol" -- packages/contracts/contracts` prints nothing. Run `pnpm --filter @graphprotocol/graph-token build:self`, then `pnpm --filter @graphprotocol/contracts build`. Expected: both exit 0.
- [ ] **Step 3: Repoint subgraph-discovery's tests** to `TOKEN_ARTIFACTS` for SubgraphNFT, SubgraphNFTDescriptor and GraphCurationToken, and add the two test files from #1396. Run `pnpm --filter @graphprotocol/subgraph-discovery test:self`. Expected: `TBD` passing (82 before the added tests).
- [ ] **Step 4: Coverage.** Run the coverage gate in graph-token for the five moved files. For each regression, add a direct test in graph-token, with `_deployPkg`. Add a Review Focus 1 test for SubgraphNFT. Run `pnpm --filter @graphprotocol/graph-token test:self`. Expected: `TBD` passing, 0 failing.
- [ ] **Step 5: Add the addresses.** Add GraphCurationToken and SubgraphNFTDescriptor for chains `421614` and `42161` to `packages/horizon/addresses.json`, copied unchanged from `packages/contracts/addresses.json`, and copy the file to `address-book/src/horizon/addresses.json`. Expected: `diff` prints nothing. Note the toolshed name-list warning in the PR.
- [ ] **Step 6: Remove `subgraph-discovery` from deployment.** Delete the cases P1 added. Expected: `git grep -n "subgraph-discovery" -- packages/deployment` prints nothing. Run `pnpm --filter @graphprotocol/deployment test:self`. Expected: PASS.
- [ ] **Step 7: Update `manifest.json`.**
- [ ] **Step 8: Commit.** `refactor(graph-token): move curation token and subgraph NFT contracts`
- [ ] **Step 9: Run the verification block.**

---

### Task P4: Move EpochManager to graph-core

**Files:**

- Move: `packages/contracts/contracts/epochs/{EpochManager,EpochManagerStorage}.sol` to `packages/graph-core/contracts/epochs/`
- Move: `packages/horizon/test/unit/epochs/EpochManager.t.sol` to `packages/graph-core/test/unit/epochs/`
- Modify: `packages/graph-core/package.json` (add `"@openzeppelin/contracts-v3": "npm:@openzeppelin/contracts@3.4.2"` to `dependencies`), `hardhat.config.ts` (filter warnings from `@openzeppelin/contracts-v3/**`). The existing Foundry remapping `@openzeppelin/=node_modules/@openzeppelin/` already covers the alias.
- Modify: `packages/horizon/test/unit/shared/ProtocolFixture.t.sol`, `foundry.toml`, `package.json` (EpochManager no longer loaded from `packages/contracts`)
- Modify: `.github/workflows/lint.yml` (`-v3` grep rule)
- Modify: `manifest.json`, `pnpm-lock.yaml`

**Interfaces:**

- Consumes: graph-core from P1.
- Produces: `@graphprotocol/graph-core/artifacts/contracts/epochs/EpochManager.sol/EpochManager.json`.

- [ ] **Step 1: Record the fork output on the parent commit.**
- [ ] **Step 2: Make the move.** Rewrite EpochManager's `@openzeppelin/contracts/math/SafeMath.sol` import to `@openzeppelin/contracts-v3/math/SafeMath.sol`. The Managed and GraphUpgradeable imports become relative. Add the alias and install. Point EpochManager in `manifest.json` at the new path. Run `pnpm --filter @graphprotocol/graph-core build:self`. Expected: exit 0. Run `pnpm --filter @graphprotocol/contracts clean && pnpm --filter @graphprotocol/contracts build`, then `pnpm check:bytecode`. Expected: EpochManager matches (the review compiled this layout and got identical creation and runtime bytecode).
- [ ] **Step 3: Move the tests.** Move the T4 suite to graph-core and switch it to `_deployPkg("EpochManager.sol:EpochManager")`. Add a Review Focus 1 test for EpochManager. Run `pnpm --filter @graphprotocol/graph-core test:self`. Expected: `TBD` passing. Run horizon's `test:self`. Expected: `TBD` passing, 2 skipped, and nothing loads EpochManager from `packages/contracts`.
- [ ] **Step 4: Add the CI rule.** Add a `lint.yml` step that fails when `git grep -l '@openzeppelin/contracts-v3' -- '*.sol' ':!packages/graph-core/**'` prints anything.
- [ ] **Step 5: Coverage gate** for `contracts/epochs/*.sol` in graph-core.
- [ ] **Step 6: Check the lockfile.**
- [ ] **Step 7: Commit.** `refactor(graph-core): move EpochManager`
- [ ] **Step 8: Run the verification block.**

---

### Task P5: Remove `legacy`'s mainnet bytecode check

**Files:**

- Delete: `packages/legacy/scripts/{fetch-verified,record-mainnet,verify}.mjs`, `mainnet.json`, `targets.json`
- Create: `packages/legacy/scripts/check-sources.mjs`
- Modify: `packages/legacy/scripts/{lib,lib.test}.mjs` (keep only what the source-hash check uses), `package.json` (`test:self` runs `node --test 'scripts/*.test.mjs' && node scripts/check-sources.mjs`; remove the solc-js dependencies), `README.md`, `pnpm-lock.yaml`

The check runs in CI only through `test:self`; there is no separate CI job.

- [ ] **Step 1: Reduce the scripts to the source-hash check.** `check-sources.mjs` runs `checkSources` on every bundle under `verified/` and exits 1 listing any changed, extra or missing file. Keep the `lib.test.mjs` cases for `checkSources` and drop the rest. Expected: `git grep -nE 'solc|mainnet\.json|targets\.json|RPC' -- packages/legacy ':!packages/legacy/verified' ':!packages/legacy/audits'` prints only README lines. Edit one byte of a file under `verified/`, run `test:self`, and confirm it fails naming that file; restore the file. The ignore entries for `verified/` stay.
- [ ] **Step 2: Rewrite the README.** One section per bundle with the contract, its mainnet address, compiler version, and its Etherscan and Sourcify links. State that the files were verified to reproduce mainnet bytecode when the package was created (the D2 commit), and that Sourcify and Etherscan are the authority.
- [ ] **Step 3: Check the lockfile** drops the solc-js entries and nothing else of note.
- [ ] **Step 4: Commit.** `chore(legacy): keep only the source-hash check`
- [ ] **Step 5: Run the verification block.**

---

### Task P6: Simplify Ignition

**Files:**

- Delete, in both `packages/horizon` and `packages/subgraph-service`:
  - `ignition/modules/migrate/`, `ignition/configs/migrate.*`, `ignition/deployments/`
  - `scripts/{pre-verify,post-verify,integration}`, and in horizon `scripts/{flatten-verify,verify-debug}`
  - `test/integration/`, `test/deployment/`, `addresses-integration-tests.json`
  - `tasks/test/{seed,ownership}.ts`, `tasks/transitions/delegation-slashing.ts`
- Delete: `packages/subgraph-service/ignition/modules/ServiceRegistry.ts`, and `packages/subgraph-service/tenderly.config.json` if it holds only `externalArtifacts`
- Modify: `tasks/deploy.ts` in both (remove `deploy:migrate`), the task files that register `test:integration`, the module files that export `Migrate*` modules, `packages/subgraph-service/ignition/modules/DisputeManager.ts` (remove `LegacyDisputeManager`), the protocol configs (remove `legacyDisputeManagerAddress`, `legacyServiceRegistryAddress`)
- Modify: every module importing `@graphprotocol/contracts-7.3.0/...`
- Modify: `package.json` in both (remove the alias and the `test:integration`, `test:deployment` and verify scripts)
- Modify: `packages/horizon/tenderly.config.json` (remove `externalArtifacts`, and the `L2Curation` and `RewardsManager` entries from `verifyList`), `packages/toolshed/src/hardhat/tenderly.ts` if `externalArtifacts` support is removed, plus a toolshed changeset if its exports change
- Modify: root `CLAUDE.md` and both packages' `README.md` (remove `deploy:migrate`, `test:integration`, `test:deployment`)
- Create: a CI job that runs `deploy:protocol` on a local Hardhat network
- Modify: `pnpm-lock.yaml`

- [ ] **Step 1: Tag the parent commit** `ignition-records-final`, so the deleted records and flows are one checkout away. Tag it only once P5 is merged into the base branch, so the tagged commit is never rewritten. Mention the tag in the PR. The tag is pushed only with the user's approval.
- [ ] **Step 2: List what uses each file before deleting it.** Run `git grep` for every task, script and module name above, outside the files being deleted. Expected: only `deploy.ts` task registrations, `package.json` scripts, docs and the files themselves. Check `local-network/containers/core/graph-contracts/run.sh` uses only `deploy:protocol`. Check whether any ops runbook uses `transition:enable-delegation-slashing`; if one does, keep that task and report it. Report anything else before continuing.
- [ ] **Step 3: Delete the migrate flow, the deployment records, the verification scripts and the migration-based suites.** Update the docs.
- [ ] **Step 4: Repoint imports.** Controller, GraphProxy, GraphProxyAdmin and EpochManager go to `@graphprotocol/graph-core/artifacts/...`. L2GraphToken, L2GraphTokenGateway, GraphCurationToken, SubgraphNFT and SubgraphNFTDescriptor go to `@graphprotocol/graph-token/artifacts/...`. RewardsManager, L2GNS and L2Curation stay on `@graphprotocol/contracts/artifacts/...`. Remove the alias and install. Expected: `git grep -n 'contracts-7.3.0' -- . ':!docs/contracts-removal' ':!**/CHANGELOG.md'` prints nothing. Run the TypeScript check in both packages.
- [ ] **Step 5: Add the CI job.** It builds the workspace and runs `npx hardhat deploy:protocol --network hardhat --subgraph-service-config localNetwork` in subgraph-service. Run the same command locally. Expected: exit 0, and the written address books contain `L2Curation`, `L2GNS`, `SubgraphNFT`, `GraphCurationToken` and `RewardsManager` with code at each address. Delete any journal it creates.
- [ ] **Step 6: Commit.** `chore(ignition): keep only deploy:protocol and read live artifacts`
- [ ] **Step 7: Run the verification block.**

---

Phase 2a (deleting `packages/contracts`) and Phase 2b (`npm deprecate`) follow Phase P and are planned with it.
