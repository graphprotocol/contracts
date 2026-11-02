# Contracts Removal — Phase 1 (Moves) and Phase 2a (Removal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move every live contract out of `packages/contracts` into the package that owns it, with identical bytecode ignoring metadata, then delete `packages/contracts`.

**Architecture:**

- Moves run bottom-up, one PR per step: graph-core, graph-token, subgraph-discovery, then EpochManager into horizon and RewardsManager into issuance. Each step removes the moved package's dependency on `packages/contracts`, so no cycle forms.
- The three 0.7.6 packages keep the same subpaths under `contracts/`, so artifact paths and coverage-baseline keys don't change. They get their own Hardhat 2 config, and Foundry compiles their sources pinned to 0.7.6.
- horizon and issuance hold their moved files in `contracts/legacy-0.7/`, selected by per-file compiler overrides.

**Tech Stack:** pnpm workspaces, Hardhat 2 and 3, Foundry 1.8.3, solc 0.7.6 and 0.8.35, OpenZeppelin 3.4.2 and 5.4, Node 24.

**Spec:** `docs/contracts-removal/design.md` (§2, §3, §4, §5, "PR sequence → Phase 1 and Phase 2").

## Global Constraints

- Each task is a draft PR in one chain, the same way as Phase D: P1 targets `chore/contracts-removal-phase-0` (#1373), and each later task targets the one before. Nothing goes to main before the audit.
- Conventional commits, no Co-Authored-By line and no Claude attribution in commits or PRs.
- Moves use `git mv`. The only source edits allowed in moved `.sol` files are import paths, and Managed's pragma going from `^0.7.6` to `^0.7.6 || ^0.8.27`.
- 0.7.6 settings are exactly solc 0.7.6, optimizer enabled, 200 runs, no `evmVersion`, no `viaIR`, default metadata.
- Cross-package Solidity imports use `@graphprotocol/<package>/contracts/<subpath>`. Imports within a package stay relative.
- `@graphprotocol/contracts-7.3.0` imports and the 11 alias artifacts don't change. Journals under `ignition/deployments/` don't change.
- Issuance's 0.8 code never imports graph-core's Managed or graph-token's TokenUtils. Issuance's code and tests never use horizon, subgraph-discovery or graph-token.
- No RPC URL or API key is ever written to a file, commit, report or PR. RPC URLs are passed only as inline env vars.
- `reference.json` and `coverage-baseline.json` are never regenerated. Only `manifest.json` paths change.
- Run `pnpm install --no-frozen-lockfile` right after any `package.json` edit, before the next build. The lockfile picks up unrelated patch bumps, so don't require an additive diff. Instead, check that it changes no solc, OpenZeppelin, Hardhat or forge-std version.

**Verification for every PR**, run from the repo root after committing. It doesn't replace CI's lint job (`lint.yml`):

```bash
pnpm install --frozen-lockfile
pnpm -r --sequential run build
pnpm test:scripts
pnpm check:bytecode
pnpm -r --sequential run test:self
pnpm lint:sol; git status --short
git diff -M HEAD~1 -- 'packages/*/contracts/**/*.sol' | grep -E '^[-+]' | grep -vE '^(\+\+\+|---)|^[-+]\s*(import|pragma|\}? ?from)|^[-+]\s+\w+,?$'
FORK_NETWORK=arbitrumSepolia pnpm --filter @graphprotocol/deployment exec hardhat deploy --tags sync --skip-prompts --network fork
```

Expected:

- All exit 0 except the `grep` line. `check:bytecode` prints `OK: 21 contracts match`.
- `git status` prints nothing. `lint:sol`'s exit code only reflects its final `pnpm todo`, so `git status` is the real check that nothing was reformatted.
- The `grep` line prints nothing: moved and consumer contracts changed only in import and pragma lines. If it prints anything, the commit hook rewrote a file. The moved files pass prettier and solhint today, so this shouldn't happen. Stop and report rather than bypass the hook.

For the fork check, run the last command once on the parent commit and save its output to the scratchpad before starting the task. The two outputs must match. The public RPC default needs no secret, and a private one goes in as an inline `ARBITRUM_SEPOLIA_RPC=`. This check can't see a missing artifact, because `tryLoadArtifactFromSource` swallows the error, so P1 adds a registry test that can.

**Rebuild rule:** after a failed Hardhat compile in horizon or subgraph-service, run `rm -rf build cache` before retrying. `isProjectBuilt` passes on a partial build, and `loadTasks` then crashes on missing artifacts.

**TypeScript check:** `npx tsc --noEmit | grep TS2307`, in the named package, must print nothing. Plain `tsc` can't exit 0, because horizon and subgraph-service have unrelated errors today.

**Hardhat 2 dbg check**, for a package and contract name: after `scripts/pre-verify spike-<task>` in that package, read `buildInfo` from `ignition/deployments/spike-<task>/artifacts/<Name>#<Name>.dbg.json`, and assert with `jq` that the build-info it points at has the artifact's `sourceName` under `input.sources`, and that the source contains the given text. Then delete `ignition/deployments/spike-<task>` and restore `build/` with a rebuild, so `git status` prints nothing.

**Coverage gate** for P1, P2 and P3, run in the moved package:

```bash
forge coverage --report lcov --report-file /tmp/<pkg>.lcov
node ../../scripts/contracts-migration/summarize-coverage.mjs /tmp/<pkg>.lcov /tmp/<pkg>.json
node ../../scripts/contracts-migration/compare-coverage.mjs ../../scripts/contracts-migration/coverage-baseline.json /tmp/<pkg>.json <moved contract paths>
```

solidity-coverage and forge count lines differently (Multicall is 6/8 in the baseline and 6/9 in forge with the same 6 hits), so line percentages can't be gated directly. The gate fails if a function hit in the baseline isn't hit now. It also prints each file whose line percentage is below baseline. List those files in the PR with a reason, or add a test. Never lower the baseline.

## Review Focus

1. **A test runs different code from what deploys.** Foundry compiles dual-pragma contracts as 0.8.35 with the optimizer off unless pinned, and they would still pass. P1, P2 and P3 each have a test that Foundry's bytecode equals the Hardhat artifact's, ignoring metadata.
2. **`RealRewardsHarness` silently falls back to its mock.** If `RM_ARTIFACT` is wrong, `vm.exists` is false and the dependent tests skip rather than fail. P5 requires 0 skipped in `packages/testing`.
3. **`pre-verify` exits 0 and points at the wrong build.** A Hardhat 3 artifact has no `.dbg.json`, so the 7.3.0 dbg left by the alias copy wins, and it describes a RewardsManager without `reclaimRewards`. From P4, `find` also sees two `EpochManager.dbg.json` files and keeps whichever comes first. P3, P4 and P5 run the dbg check in both packages.
4. **The commit hook rewrites moved files.** lint-staged runs on renamed `.sol` files, and comment or formatting edits don't change bytecode, so `check:bytecode` can't see them. The `grep` line in the verification block catches this.
5. **A package loads only when a command runs.** `require.resolve` in `packages/deployment`, and Ignition imports in dynamically loaded `migrate/*` modules, can pass `build`. P1's registry test and the TypeScript check cover both.

---

### Task P1: Move the governance and proxy contracts to graph-core

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
- Scripts: `build` is `pnpm build:dep && pnpm build:self`, `build:self` is `hardhat compile --quiet`, `clean` is `rm -rf artifacts/ cache/ types/ forge-artifacts/ cache_forge/ coverage/`, and `lint:sol` matches `packages/contracts`.
- devDependencies: `@graphprotocol/interfaces`, `hardhat`, `hardhat-ignore-warnings`, `@nomicfoundation/hardhat-verify` 2.1.1, `@typechain/hardhat`, `@typechain/ethers-v5`, `typechain`, `ethers ^5.7.2`, `@ethersproject/{abi,bytes,providers}`, `ts-node`, `typescript`, `solhint`, `prettier`, `prettier-plugin-solidity`, `forge-std`, each at the version `packages/contracts` uses. Remove `@graphprotocol/contracts`.
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

### Task P3: Move the discovery and curation contracts to subgraph-discovery

**Files:**

- Move: `l2/discovery/{L2GNS,L2GNSStorage}.sol`, `l2/curation/L2Curation.sol`, `discovery/{GNS,GNSStorage,SubgraphNFT,SubgraphNFTDescriptor}.sol`, `curation/{CurationStorage,GraphCurationToken}.sol`, `libraries/{Base58Encoder,HexStrings}.sol`, `base/Multicall.sol`
- Create: `packages/subgraph-discovery/hardhat.config.ts`, `README.md`, `.solhint.json`, `prettier.config.cjs`, `.changeset/subgraph-discovery-initial.md` (`major`), `.changeset/horizon-curation-addresses.md` (`@graphprotocol/address-book: minor`), `.changeset/toolshed-tenderly-sources.md` (`@graphprotocol/toolshed: minor`)
- Modify: `packages/subgraph-discovery/{package.json,foundry.toml}` and tests
- Modify: horizon `ignition/modules/periphery/{Curation,GNS}.ts`, subgraph-service `ignition/modules/{Curation,GNS}.ts`, both `scripts/pre-verify` and `package.json`
- Modify: `packages/horizon/tenderly.config.json`, `packages/toolshed/src/hardhat/tenderly.ts`
- Modify: `packages/horizon/addresses.json`, `packages/address-book/src/horizon/addresses.json`
- Modify: `packages/deployment/lib/contract-registry.ts` (L2Curation, L2GNS), `package.json`, `test/bytecode-comparison.test.ts:235`
- Modify: `manifest.json`, `publish.yml`, `.gitignore`, `pnpm-lock.yaml`

**Interfaces:**

- Consumes: graph-core, graph-token, the same `_deployPkg` helper, `TOKEN_ARTIFACTS`, the new package setup.
- Produces: `TenderlyConfig.externalArtifacts` as `{ source: string; buildInfo: string }[]`; `@graphprotocol/subgraph-discovery/artifacts/contracts/l2/{curation,discovery}/...`.

Package setup follows P2 without `arbos-precompiles`. Dependencies are graph-core, graph-token and interfaces.

- [ ] **Step 1: Make the move** and rewrite imports. Apply the package setup, install, and build the package. Expected: exit 0.
- [ ] **Step 2: Switch `PKG_ARTIFACTS` to `_deployPkg` ids,** adding the helper, and add the Review Focus 1 test for L2GNS. Run `test:self`. Expected: 83 passing.
- [ ] **Step 3: Switch the L2GNS and L2Curation Ignition imports** in the four module files to `@graphprotocol/subgraph-discovery/artifacts/...`. Add the devDependency to horizon and subgraph-service, and install. Run the TypeScript check in both.
- [ ] **Step 4: Update both `pre-verify` scripts.** Copy L2Curation and L2GNS from `../subgraph-discovery/artifacts`. Add a line copying its `build-info`, and keep the `../contracts/artifacts/build-info` line, because RewardsManager's dbg points there until P5.
- [ ] **Step 5: Check Review Focus 3.** In horizon and subgraph-service, run the Hardhat 2 dbg check for L2GNS (source contains `L2GNS`) and for RewardsManager (source contains `reclaimRewards`). Run `npx hardhat deploy:protocol --network hardhat` in horizon. Expected: exit 0. Delete any journal it creates, so `git status` prints nothing.
- [ ] **Step 6: Make Tenderly read several sources.** Change `externalArtifacts` to an array in `tenderly.ts`, looping the existing `rsync` in `copyExternalArtifacts`. Set horizon's config to `../subgraph-discovery/artifacts` (L2Curation) and `../contracts/artifacts` (RewardsManager), each with its `build-info`. Toolshed has no test harness, so run `copyExternalArtifacts` once with `tsx`, and confirm both contracts appear in `.tenderly-artifacts`, then delete that folder.
- [ ] **Step 7: Add the addresses.** Add GraphCurationToken and SubgraphNFTDescriptor to chain `421614` and `42161` in `packages/horizon/addresses.json`, copying their entries unchanged from `packages/contracts/addresses.json`, and copy the file to `packages/address-book/src/horizon/addresses.json` as a regular file. Expected: `diff` of the two files prints nothing. These names aren't in toolshed's `GraphHorizonContractNameList`, so toolshed logs a warning on load. Leave the list alone and say so in the PR.
- [ ] **Step 8: Update deployment** registry entries to `{ type: 'subgraph-discovery', path: 'l2/curation', name: 'L2Curation' }` and `{ type: 'subgraph-discovery', path: 'l2/discovery', name: 'L2GNS' }`, the test, and `manifest.json` for L2GNS, L2Curation, GraphCurationToken, SubgraphNFT, SubgraphNFTDescriptor.
- [ ] **Step 9: Add `subgraph-discovery` to `publish.yml`,** and check the lockfile.
- [ ] **Step 10: Commit.** `refactor(subgraph-discovery): move discovery and curation contracts`
- [ ] **Step 11: Run the verification block and the coverage gate** for the moved contracts.

---

### Task P4: Move EpochManager to horizon

**Files:**

- Move: `packages/contracts/contracts/epochs/{EpochManager,EpochManagerStorage}.sol` to `packages/horizon/contracts/legacy-0.7/epochs/`
- Create: `packages/horizon/.prettierignore`
- Modify: `packages/horizon/hardhat.config.ts`, `foundry.toml`, `package.json`, `.solhintignore`, `scripts/pre-verify`, `test/unit/shared/ProtocolFixture.t.sol`, `test/unit/epochs/EpochManager.t.sol`
- Modify: `packages/subgraph-service/scripts/pre-verify`
- Modify: `.solhintignore`, `.prettierignore`, `scripts/lint-staged-run.sh`, `.github/workflows/lint.yml`, `manifest.json`, `pnpm-lock.yaml`

**Interfaces:**

- Consumes: graph-core.
- Produces: `packages/horizon/build/contracts/contracts/legacy-0.7/epochs/EpochManager.sol/EpochManager.json`; the `-v3` grep rule and `legacy-0.7` ignores, which P5 reuses.

Only `@openzeppelin/contracts-v3` is needed, as `npm:@openzeppelin/contracts@3.4.2`, because neither moved group imports the upgradeable package. horizon's Ignition EpochManager stays on the 7.3.0 alias because its bytecode is unchanged.

- [ ] **Step 1: Make the move.** Rewrite `../governance/Managed.sol` and `../upgrades/GraphUpgradeable.sol` to graph-core, and SafeMath to `@openzeppelin/contracts-v3/math/SafeMath.sol`. Add the alias, raise the `@openzeppelin/contracts` floor to `^5.4.0`, and install.
- [ ] **Step 2: Add the compiler.** In `hardhat.config.ts`:

  ```ts
  const legacy076 = { version: '0.7.6', settings: { optimizer: { enabled: true, runs: 200 } } }
  solidity: {
    compilers: [baseConfig.solidity, legacy076],
    overrides: {
      'contracts/legacy-0.7/epochs/EpochManager.sol': legacy076,
      'contracts/legacy-0.7/epochs/EpochManagerStorage.sol': legacy076,
    },
  },
  ```

  Pragma selection can't do this: Hardhat joins transitive pragmas with spaces, and the OR picks 0.8.35. Run `rm -rf build cache && pnpm --filter @graphprotocol/horizon build:self`. Expected: exit 0.

- [ ] **Step 3: Update Foundry.** Add `skip = ["contracts/legacy-0.7/**"]` and `[lint] ignore` for it. Change the fixture's `PKG_ARTIFACTS` to `build/contracts/contracts/legacy-0.7/`, change the test's path to `epochs/EpochManager.sol/EpochManager.json`, and remove `node_modules/@graphprotocol/contracts/artifacts` from `fs_permissions`. Run `pnpm --filter @graphprotocol/horizon test:self`. Expected: 590 passing and 2 skipped.
- [ ] **Step 4: Keep `pre-verify` on the deployed build.** Add `-not -path '*/legacy-0.7/*'` to the dbg `find` in both scripts. Run the Hardhat 2 dbg check for EpochManager in both packages, with `sourceName` `contracts/epochs/EpochManager.sol`, the 7.3.0 path Ignition deployed from. Also confirm `find build/contracts/contracts -name 'EpochManager.dbg.json' -not -path '*/legacy-0.7/*'` prints exactly one path, so the result no longer depends on `find` order.
- [ ] **Step 5: Update the lint rules.**
  - Add `packages/*/contracts/legacy-0.7/` to root `.solhintignore` and `.prettierignore`, and `/contracts/legacy-0.7/` to `IGNORE_SUBSTRINGS` in `scripts/lint-staged-run.sh`.
  - Add `contracts/legacy-0.7/` to `packages/horizon/.solhintignore` and a new `packages/horizon/.prettierignore`, because package scripts and CI's full mode run from inside the package and read only that folder's ignore files.
  - Add `legacy-0.7` to the `grep -v` on `CHANGED_SOL` at `lint.yml:67`, because solhint exits 255 when every file it's given is ignored.
  - Add a `lint.yml` step that fails when `git grep -l '@openzeppelin/contracts-v3' -- '*.sol' ':!packages/*/contracts/legacy-0.7/**'` prints anything.
  - Run `pnpm lint:sol` in horizon with a deliberately misformatted legacy file, and confirm it isn't rewritten. Restore the file.
- [ ] **Step 6: Check `Managed` lookups.** horizon now has two `Managed` artifacts, so a lookup by bare name would fail. Run `git grep -nE "(getContractFactory|readArtifact|getArtifact)\(['\"]Managed" -- packages/horizon packages/subgraph-service packages/toolshed`. Expected: no output. Run the TypeScript check in horizon.
- [ ] **Step 7: Point `manifest.json` at the new EpochManager path,** and check the lockfile.
- [ ] **Step 8: Commit.** `refactor(horizon): move EpochManager to legacy-0.7`
- [ ] **Step 9: Run the verification block.** Also check the 0.8 build-info still shows `viaIR` true and `evmVersion` cancun, and EpochManager's shows neither.

---

### Task P5: Move RewardsManager to issuance

Schedule this when no RewardsManager PRs are in flight.

**Files:**

- Move: `rewards/{RewardsManager,RewardsManagerStorage}.sol` and `staking/libs/MathUtils.sol` to `packages/issuance/contracts/legacy-0.7/rewards/`
- Modify: `packages/issuance/{hardhat.base.config.ts,foundry.toml,package.json}`, `test/unit/shared/ProtocolFixture.t.sol`, `test/unit/rewards-manager/shared.t.sol`
- Create: `packages/issuance/.solhintignore`, `.prettierignore`, `scripts/export-hh2-artifact.mjs`, `export-hh2-artifact.test.mjs`
- Modify: horizon `ignition/modules/periphery/RewardsManager.ts`, both `scripts/pre-verify`, `tenderly.config.json`, `package.json`; subgraph-service `package.json`
- Modify: `packages/testing/test/harness/RealRewardsHarness.t.sol`, `foundry.toml`, `package.json`
- Modify: `packages/deployment/lib/{artifact-loaders,contract-registry,deploy-implementation,deployment-validation}.ts`, `scripts/generate-abis.ts`, `tasks/verify-contract.ts`, `test/bytecode-comparison.test.ts`, `docs/Design.md`, `package.json`
- Modify: `manifest.json`, `count-patterns.txt`, `.gitignore`, `.prettierignore`, `pnpm-lock.yaml`

**Interfaces:**

- Consumes: graph-core, the `legacy-0.7` ignores and `-v3` rule from P4, the Tenderly array from P3.
- Produces: `packages/issuance/artifacts-hh2/contracts/rewards/RewardsManager.sol/{RewardsManager.json,RewardsManager.dbg.json}` and `artifacts-hh2/build-info/<id>.json`; deployment no longer has a `'contracts'` source; nothing but `packages/contracts` itself depends on `@graphprotocol/contracts`.

- [ ] **Step 1: Make the move.** Rewrite imports to graph-core, `./MathUtils.sol` and `@openzeppelin/contracts-v3/...`. Add `@openzeppelin/contracts-v3` to issuance, remove `@graphprotocol/contracts` from its package.json, and install.
- [ ] **Step 2: Add the compiler.** In `hardhat.base.config.ts`, give `solidity` `compilers: [issuanceSolidityConfig, legacy076]` with `overrides` for the three moved files. Run `pnpm --filter @graphprotocol/issuance build:self`. Expected: exit 0, and `types/legacy-0.7/rewards/` exists. Check in the build-info that `IGraphToken`'s `IERC20` resolved to `@openzeppelin/contracts@3.4.2` and the 0.8 job uses 5.4.0.
- [ ] **Step 3: Update Foundry and lint.** Add `skip` and `[lint] ignore`. Set `PKG_ARTIFACTS` to `artifacts/contracts/legacy-0.7/`, change the test's path to `rewards/RewardsManager.sol/RewardsManager.json`, and remove `node_modules/@graphprotocol/contracts/artifacts` from `fs_permissions`. Add `contracts/legacy-0.7/` to the new `.solhintignore` and `.prettierignore`. Run `pnpm --filter @graphprotocol/issuance test:self`. Expected: 799 passing.
- [ ] **Step 4: Write `export-hh2-artifact` tests first.** Given issuance's real build output, assert:
  - the exported artifact has `_format: 'hh-sol-artifact-1'` and `sourceName` `contracts/legacy-0.7/rewards/RewardsManager.sol`;
  - `RewardsManager.dbg.json`'s `buildInfo` is `../../../build-info/<id>.json`;
  - the build-info has `_format: 'hh-sol-build-info-1'`, `solcVersion` and `solcLongVersion`, and `input.sources` contains `sourceName`;
  - no key in `input.sources` or `output.contracts` starts with `project/` or `npm/`, and `input.settings` has no `remappings`;
  - compiling that `input` with solc-js 0.7.6 gives RewardsManager bytecode matching `reference.json`, using `scripts/lib/bytecode.mjs`.

  Add `solc-0.7.6` as `npm:solc@0.7.6`. Run with `node --test`. Expected: FAIL.

- [ ] **Step 5: Implement `export-hh2-artifact.mjs`.**
  - Hardhat 3 writes several `solc-0_7_6-*` build-infos, so find RewardsManager's through the artifact's `buildInfoId`.
  - Rewrite `project/` and `npm/<pkg>@<version>/` source keys in both `input` and `output`. `<version>` can be `local` for workspace packages.
  - Take plain names from the imports that reach each source, not from the key: `npm/@openzeppelin/contracts@3.4.2/` is `contracts-v3` for SafeMath and IERC165, and `contracts` for IERC20. Throw if a source is reached under two names.
  - Merge `<id>.output.json`'s `output` into the build-info.
  - Run the script at the end of `build:self`. Add `artifacts-hh2/` to `clean`, `files`, root `.gitignore` and root `.prettierignore`, and add `node --test scripts/*.test.mjs` to `test:self`. Expected: PASS.

  Metadata differs from the deployed build, so say in the PR that Etherscan may record a partial match.

- [ ] **Step 6: Switch Ignition.** Point `ignition/modules/periphery/RewardsManager.ts` at `@graphprotocol/issuance/artifacts/contracts/legacy-0.7/rewards/RewardsManager.sol/RewardsManager.json`. In both `package.json` files remove `@graphprotocol/contracts`; horizon adds `@graphprotocol/issuance`. Install, then run the TypeScript check in both. Run `npx hardhat deploy:protocol --network hardhat` in horizon, and confirm the artifact's `deployedBytecode` contains the `reclaimRewards` selector `2054467b`. Delete any journal it creates.
- [ ] **Step 7: Update `pre-verify` and Tenderly.** Copy RewardsManager and `build-info` from `../issuance/artifacts-hh2` in both scripts, and remove every remaining `../contracts` line. Point Tenderly's second entry at `../issuance/artifacts-hh2`.
- [ ] **Step 8: Check Review Focus 3.** In horizon and subgraph-service, run the Hardhat 2 dbg check for RewardsManager, with `sourceName` `contracts/legacy-0.7/rewards/RewardsManager.sol` and source containing `reclaimRewards`.
- [ ] **Step 9: Update testing.** Set `RM_ARTIFACT` to `node_modules/@graphprotocol/issuance/artifacts/contracts/legacy-0.7/rewards/RewardsManager.sol/RewardsManager.json`, update `fs_permissions`, remove `@graphprotocol/contracts`, and install. Run `pnpm --filter @graphprotocol/testing test:self`. Expected: 24 passing, 0 skipped.
- [ ] **Step 10: Finish deployment.** Set the registry entry to `{ type: 'issuance', path: 'contracts/legacy-0.7/rewards/RewardsManager.sol/RewardsManager' }`. Remove `type: 'contracts'`, `loadContractsArtifact`, the `@graphprotocol/contracts` dependency and the `deploy-implementation.ts:299` legacy `artifactPath` default, which needs `config.artifact` required instead. Change `build:clean` to `pnpm --filter '@graphprotocol/deployment^...' clean && pnpm build:deps`. Update `Design.md`, `generate-abis.ts` and the bytecode test. Install, then run `pnpm --filter @graphprotocol/deployment test:self` and `build:self`. Expected: exit 0.
- [ ] **Step 11: Update `manifest.json` and `count-patterns.txt`,** and check the lockfile.
- [ ] **Step 12: Commit.** `refactor(issuance): move RewardsManager to legacy-0.7`
- [ ] **Step 13: Run the verification block.** Expected: `git ls-files 'packages/contracts/contracts/*.sol'` prints nothing, and `git grep -n '"@graphprotocol/contracts"' -- 'packages/*/package.json'` prints only `packages/contracts/package.json`.

---

### Task P6: Delete `packages/contracts` (Phase 2a)

**Files:**

- Delete: `packages/contracts/` with `rm -rf`, including `.env.example`, `TESTING.md`, `DEPLOYMENT.md`, `README.md`, `scripts/` and `tsconfig.json`. The `@graphprotocol/contracts@7.3.0` git tag preserves them.
- Modify: `.github/workflows/publish.yml`, `.gitignore`, `README.md`, `CLAUDE.md`, `count-patterns.txt`, `docs/IGraphProxyAdminInterfaceFix.md`, `docs/ForgeLintSymlinkIssue.md`, `docs/Linting.md`, `packages/issuance/docs/testing/reo/{RewardsConditionsTestPlan,SubgraphDenialTestPlan}.md`, `packages/toolshed/src/deployments/{horizon,subgraph-service}/contracts.ts`, `pnpm-lock.yaml`

**Interfaces:**

- Consumes: P5's state, where nothing depends on the package.
- Produces: nothing. `scripts/contracts-migration/coverage-baseline.json` and `reference.json` stay.

- [ ] **Step 1: Confirm the Docker image doesn't use it.** Run `git grep -nE 'packages/contracts\b|graphprotocol/contracts"|@graphprotocol/sdk' -- Dockerfile .github/workflows/publish-image.yml`. Expected: no output.
- [ ] **Step 2: Delete the package and make the edits.** Remove `contracts` from `publish.yml`, `.gitignore:32`, `:43` and the `arbitrum-addresses-local.json` line, the root README row, and the `packages/contracts` command and package entry in `CLAUDE.md`. Add the three new packages to the README table and `CLAUDE.md`. Update docs to name the owning package. Point toolshed's comments at the owning packages. Remove the `count-patterns.txt` lines for it.
- [ ] **Step 3: Update the lockfile.** Run `pnpm install --no-frozen-lockfile`.
- [ ] **Step 4: Run the design's final search.** Run `git grep -InE '@graphprotocol/contracts([^-[:alnum:]]|$)|packages/contracts([^-[:alnum:]]|$)|\.\./contracts/artifacts' -- ':!pnpm-lock.yaml' ':!**/CHANGELOG.md' ':!packages/*/ignition/deployments/**' ':!docs/contracts-removal' ':!scripts/contracts-migration/test-mapping/**' ':!packages/legacy/verified/**'`. Expected: no output.
- [ ] **Step 5: Commit.** `refactor: remove packages/contracts`
- [ ] **Step 6: Run the verification block from a clean tree.** First run `pnpm clean:all`, so a leftover `packages/contracts` artifact can't hide a dependency.

Phase 2b, `npm deprecate` on `@graphprotocol/contracts` and `@graphprotocol/sdk`, is a manual step for the user after this. Each new package also needs a Trusted Publisher entry on npmjs.com before its first publish, or the workflow returns 403.
