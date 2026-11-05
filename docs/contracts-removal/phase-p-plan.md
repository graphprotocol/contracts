# Contracts Removal — Phase P (Ports to 0.8) and Phase 2 (Final Removal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port RewardsManager, L2GNS and L2Curation to Solidity 0.8 in their domain packages without changing behaviour or storage layout, then delete `packages/contracts`.

**Architecture:**

- Pa moves `interfaces` to OpenZeppelin 5, so a 0.8 RewardsManager can compile in issuance's Hardhat 3 build.
- Pb ports RewardsManager, RewardsManagerStorage and MathUtils into issuance. Pc ports L2GNS, GNS, L2Curation, their storage contracts and Multicall into subgraph-service, adds `InitializableV3`, and deletes `subgraph-discovery`.
- Each port keeps the files' subpaths under `contracts/`, so coverage-baseline keys don't change. The ported files compile with their own per-file settings, without `viaIR`. The T3 and T5 suites run against both the pre-port 0.7.6 artifact (a committed fixture) and the 0.8 build.
- 2a deletes the then-empty `packages/contracts` and every reference to it. 2b is a manual `npm deprecate`.

**Tech Stack:** pnpm workspaces, Hardhat 2 (subgraph-service, horizon), Hardhat 3 (issuance), Foundry 1.8.3, solc 0.7.6 and 0.8.35, OpenZeppelin 3.4.2 and 5.4, Ignition, Node 24.

**Spec:** `docs/contracts-removal/design.md` (§3 "Ports to 0.8", §4 "Differential tests for ports", §5, "PR sequence → Phase P" and "Phase 2", Verification).

Phase 1 is merged into #1373 (head `813cac0a`). Counts marked `TBD` are filled in by a dry run before each task starts.

## Global Constraints

- Each task is a draft PR in one chain: Pa targets `chore/contracts-removal-phase-0` (#1373), and each later task targets the one before. Nothing goes to main before the audit.
- Conventional commits, no Co-Authored-By line and no Claude attribution in commits or PRs.
- A port PR has exactly two commits. The first is a pure `git mv` of the ported contracts: every entry in `git show --name-status -M HEAD~1` is `R100`. It doesn't build; the PR says so. The second holds the port and everything else. Auditors read `git show <second> -- 'packages/<pkg>/contracts/**' <compile config files>`.
- Allowed source changes in a port, and nothing else: the pragma becomes `^0.8.27`; SafeMath calls become checked operators; OpenZeppelin 3 imports become OpenZeppelin 5 or local equivalents; whatever 0.8 requires to compile; and the design's known port points (§3).
- Ported files compile with solc 0.8.35, optimizer enabled, 200 runs (the 0.7.6 build's value), `evmVersion: cancun`, no `viaIR`. They keep their subpaths under `contracts/`.
- Tests never import a ported contract's source. They reach it through interfaces or `*Like` interfaces, and deploy it with `deployCode` or from a fixture.
- Issuance's code and tests never use horizon, subgraph-service or graph-token.
- `reference.json` and `coverage-baseline.json` are never regenerated. A ported contract's entries are deleted from `manifest.json` and `reference.json` by hand, and nothing else changes in them.
- No RPC URL or API key is ever written to a file, commit, report or PR. RPC URLs are passed only as inline env vars.
- Run `pnpm install --no-frozen-lockfile` right after any `package.json` edit. Check the lockfile changes no solc, OpenZeppelin, Hardhat or forge-std version, except the `interfaces` OpenZeppelin change in Pa.
- Before Pb and Pc, list open PRs and security advisories that touch the contracts being ported, and stop for the user's decision if there are any. If main changes a living contract before its port is merged into the base, the port is redone on top of that change.
- The pre-port tag is `pre-port-0.7.6`, on Pb's parent commit, once Pa is merged into the base branch. The tag is pushed only with the user's approval.

**Verification for every PR**, run from the repo root after committing. It doesn't replace CI's lint job (`lint.yml`):

```bash
pnpm install --frozen-lockfile
pnpm -r --sequential run clean
pnpm -r --sequential run build
pnpm test:scripts
pnpm check:bytecode
pnpm -r --sequential run test:self
pnpm lint:sol; git status --short
pnpm --filter @graphprotocol/issuance --filter @graphprotocol/subgraph-service lint:forge
(cd packages/subgraph-service && npx hardhat deploy:protocol --network hardhat --subgraph-service-config localNetwork)
rm -rf packages/deployment/fork
FORK_NETWORK=arbitrumSepolia pnpm --filter @graphprotocol/deployment exec hardhat deploy --tags sync --skip-prompts --network fork
```

Expected:

- All exit 0. `check:bytecode` prints `OK: 21 contracts match` in Pa, `OK: 20` from Pb and `OK: 18` from Pc.
- `git status` prints nothing after `lint:sol`. `deploy:protocol` may write address books and an Ignition journal: delete the untracked files it creates and restore the tracked address books it changed, nothing else.
- `lint:forge` reports nothing in ported files. If it does, stop and report: don't edit the port to silence it.
- Fork sync, compared with the parent commit's output: identical in Pa and 2a; only `RewardsManager` differs in Pb; only `L2GNS` and `L2Curation` differ in Pc. Record the parent's output in the scratchpad before starting. The public RPC default needs no secret, and a private one goes in as an inline `ARBITRUM_SEPOLIA_RPC=`. The `rm -rf` is required: the sync caches address books.

**Rebuild rule:** after a failed Hardhat compile in horizon or subgraph-service, run `rm -rf build cache` before retrying.

**TypeScript check:** `npx tsc --noEmit | grep TS2307`, in the named package, must print nothing.

**Coverage gate** for each port, run in the destination package:

```bash
forge coverage --report lcov --report-file /tmp/<pkg>.lcov
node ../../scripts/contracts-migration/summarize-coverage.mjs /tmp/<pkg>.lcov /tmp/<pkg>.json
node ../../scripts/contracts-migration/compare-coverage.mjs ../../scripts/contracts-migration/coverage-baseline.json /tmp/<pkg>.json <ported contract paths>
```

The gate fails if a baseline function isn't hit. Add a test for each regression, through the contract's public interface. If a test can't reach one, stop and report. List files below their baseline line percentage in the PR with a reason. Coverage compiles without the optimizer, so if a ported contract fails to deploy with `CreateContractSizeLimit`, add `--disable-code-size-limit` to the package's `test:coverage` and `test:coverage:self`.

**Port PR description** lists: that the first commit doesn't build; the tests whose expected revert data differs between the builds (or "none"); the storage-layout comparison output; the 0.8 deployed sizes; files below baseline coverage; and the fork-sync difference.

## Review Focus

1. **A ported contract compiles with other settings than intended.** An override key that doesn't match its file falls back to the package default (`viaIR` on), and a Foundry pin that doesn't apply leaves the optimizer off. Each ported deployable gets `test_Build_FoundryMatchesHardhat`, and each port step checks the Hardhat build-info.
2. **The suite runs a different build from the one requested.** If `PRE_PORT` were ignored, or the fixture were stale, both runs would pass while testing one build. `test_Build_DeploysRequestedBuild` compares the deployed code hash with the requested build's, and the fixture is compared byte for byte with the parent commit's build.
3. **Subgraph ID aliasing stops wrapping.** About 6.7% of L1 IDs wrap when aliased, and unaliasing wraps the other way. `test_GetAliasedL2SubgraphID_WrapsAroundMaxUint256` exists; Pc adds `test_GetUnaliasedL1SubgraphID_WrapsBelowZero`. Both run on both builds.
4. **`InitializableV3` changes initializer state.** L2Curation's `_initialized` and `_initializing` must stay in slot 16, and re-initialization must revert the same way. Pc adds slot and re-initialization tests that run on both builds, and compares storage layouts.
5. **The fresh-stack deployment loses a contract.** After Pc, horizon's modules get L2GNS and L2Curation artifacts from subgraph-service's task. The `deploy:protocol` run checks that the address books hold `L2Curation`, `L2GNS`, `SubgraphNFT` and `RewardsManager` with code, and that `L2Curation.curationTokenMaster()` has code.

---

### Task Pa: Move `interfaces` to OpenZeppelin 5

**Files:**

- Modify: `packages/interfaces/package.json` (`@openzeppelin/contracts` `^5.4.0` in `dependencies`; remove both OpenZeppelin `devDependencies`)
- Modify: `packages/interfaces/contracts/contracts/curation/IGraphCurationToken.sol`
- Modify: `packages/deployment/scripts/generate-abis.ts:32` (IERC165 artifact path)
- Create: `.changeset/interfaces-openzeppelin-5.md` (`@graphprotocol/interfaces: major`)
- Modify: `pnpm-lock.yaml`

**Interfaces:**

- Consumes: nothing.
- Produces: `IGraphCurationToken is IERC20` (OpenZeppelin 5), and `interfaces` resolving `@openzeppelin/contracts` 5.4 for Hardhat 3 consumers.

- [ ] **Step 1: Record the fork output and selectors on the parent commit.** Save the fork output, and for `IGraphCurationToken`, `IGraphToken` and `ISubgraphNFT` save the sorted function and event signatures from their `interfaces` artifacts: `jq -r '[.abi[] | select(.type=="function" or .type=="event") | .name + "(" + ([.inputs[].type] | join(",")) + ")"] | sort[]'`.
- [ ] **Step 2: Change the dependency** and install. Expected: the lockfile changes `interfaces`' OpenZeppelin entries and nothing else of note.
- [ ] **Step 3: Change `IGraphCurationToken`** to import `IERC20` from `@openzeppelin/contracts/token/ERC20/IERC20.sol` and extend it. Run `pnpm --filter @graphprotocol/interfaces clean && pnpm --filter @graphprotocol/interfaces build`. Expected: exit 0; `artifacts/@openzeppelin/` holds `contracts/token/ERC20/IERC20.sol`, `contracts/token/ERC721/IERC721.sol` and `contracts/utils/introspection/IERC165.sol`, and no `contracts-upgradeable`. The three signature lists equal Step 1's.
- [ ] **Step 4: Update `generate-abis.ts`** to `@graphprotocol/interfaces/artifacts/@openzeppelin/contracts/utils/introspection/IERC165.sol/IERC165.json`. Run `pnpm --filter @graphprotocol/deployment test:self`. Expected: PASS.
- [ ] **Step 5: Write the changeset.** It says the generated `IERC20Upgradeable` types are gone, the `IERC165` types moved to `utils/introspection`, and ABI parameter names follow OpenZeppelin 5 (for example `transfer(to, value)`, `setApprovalForAll(operator, approved)`), which changes the wagmi ABIs.
- [ ] **Step 6: Commit.** `feat(interfaces)!: use OpenZeppelin 5`
- [ ] **Step 7: Run the verification block.** `check:bytecode` passing shows graph-core, graph-token, L2GNS and L2Curation are unaffected.

---

### Task Pb: Port RewardsManager to issuance

**Files:**

- Move: `packages/contracts/contracts/rewards/{RewardsManager,RewardsManagerStorage}.sol` to `packages/issuance/contracts/rewards/`, and `staking/libs/MathUtils.sol` to `packages/issuance/contracts/staking/libs/`
- Create: `packages/issuance/test/fixtures/pre-port/RewardsManager.json` and `RewardsManager.storage.json`, `packages/issuance/test/unit/rewards-manager/build.t.sol`, `.changeset/issuance-rewards-manager.md` (`@graphprotocol/issuance: minor`)
- Create: `scripts/contracts-migration/compare-storage-layout.mjs`, `compare-storage-layout.test.mjs`
- Modify: issuance `hardhat.base.config.ts`, `foundry.toml`, `package.json`, `test/unit/shared/ProtocolFixture.t.sol`, `test/unit/rewards-manager/shared.t.sol`, `docs/testing/reo/{RewardsConditions,SubgraphDenial}TestPlan.md`
- Modify: horizon `ignition/modules/periphery/RewardsManager.ts`, `package.json`
- Modify: testing `test/harness/RealRewardsHarness.t.sol`, `test/integration/IndexingRewardsCollection.t.sol`, `foundry.toml`, `package.json`
- Modify: deployment `lib/contract-registry.ts:142`, `test/bytecode-comparison.test.ts`
- Modify: `scripts/contracts-migration/{manifest,reference}.json`, `count-patterns.txt:10`, `.prettierignore`, `pnpm-lock.yaml`

**Interfaces:**

- Consumes: `interfaces` on OpenZeppelin 5 (Pa).
- Produces:
  - `@graphprotocol/issuance/artifacts/contracts/rewards/RewardsManager.sol/RewardsManager.json`.
  - In each package's `ProtocolFixture`: `_isPrePort() returns (bool)`, which is `vm.envOr("PRE_PORT", false)`, and `_deployPorted(string memory id, string memory fixture) returns (address)`, which returns `deployCode(id)` or, when `_isPrePort()`, `_deployArtifact(fixture, "")`. `id` has the form `"RewardsManager.sol:RewardsManager"`. Pc copies both.
  - `compareLayouts(before, after)` in `compare-storage-layout.mjs`, returning a list of differences. The CLI is `<before.json> <after.json>`, prints them, and exits 1 if there are any.
  - Fixture layout: `test/fixtures/pre-port/<Contract>.json` (the Hardhat artifact, unchanged) and `<Contract>.storage.json` (`forge inspect` storage layout).

- [ ] **Step 1: Check in-flight work.** List open PRs whose files touch `packages/contracts/contracts/{rewards,staking/libs}/`, and the open security advisories for RewardsManager. If there are any, stop and report.
- [ ] **Step 2: Record the parent commit's outputs.** Ask the controller to tag the parent `pre-port-0.7.6` (Global Constraints). Then:
  - Run `pnpm --filter @graphprotocol/contracts clean && pnpm --filter @graphprotocol/contracts build`, then `pnpm check:bytecode`. Expected: `OK: 21`. Copy `packages/contracts/artifacts/contracts/rewards/RewardsManager.sol/RewardsManager.json` to the scratchpad.
  - Write the storage layout to the scratchpad. Run it in `packages/contracts`, passing `--out` and `--cache-path` in the scratchpad, because forge's default `cache/` would overwrite Hardhat's cache file:

    ```bash
    forge inspect contracts/rewards/RewardsManager.sol:RewardsManager storageLayout --json --use 0.7.6 \
      --contracts contracts --lib-paths node_modules \
      --remappings @openzeppelin/=node_modules/@openzeppelin/ --remappings @graphprotocol/=node_modules/@graphprotocol/ \
      --out <scratch>/out --cache-path <scratch>/cache
    ```

  - Record the fork output.

- [ ] **Step 3: Move.** `git mv` the three files. Run `git show --name-status -M HEAD` after committing. Expected: three `R100` lines. Commit `refactor(issuance): move RewardsManager from contracts`.
- [ ] **Step 4: Write the storage-layout tests first.** Cases:
  - identical layouts give `[]`;
  - a changed `slot` or `offset` is reported, naming the variable's `label`;
  - layouts that differ only in `astId`, `contract` and type ids (such as `t_contract(IRewardsIssuer)1234`) give `[]`;
  - a struct member moved inside a struct is reported (members are compared recursively);
  - a variable added at the end is reported.

  Entries are compared by `label`, `slot`, `offset`, and the referenced type's `label` and `numberOfBytes`. Run `pnpm test:scripts`. Expected: FAIL.

- [ ] **Step 5: Implement `compare-storage-layout.mjs`.** Run `pnpm test:scripts`. Expected: PASS.
- [ ] **Step 6: Port the three files** within the allowed changes: SafeMath and its import go, `IERC165` comes from `@openzeppelin/contracts/utils/introspection/IERC165.sol`, and RewardsManagerStorage's dual pragma becomes `^0.8.27`. The `+=` at the old `RewardsManager.sol:482` stays checked.
- [ ] **Step 7: Set the compile config.**
  - In `hardhat.base.config.ts`, change `issuanceBaseConfig.solidity` to `{ compilers: [issuanceSolidityConfig], overrides }`. `overrides` maps each ported file's source name to `{ version: '0.8.35', settings: { optimizer: { enabled: true, runs: 200 }, evmVersion: 'cancun' } }`.
  - In `foundry.toml`, add an `additional_compiler_profiles` entry and a `compilation_restrictions` entry that pin `contracts/rewards/**` and `contracts/staking/**` to the same settings. If Foundry can't express them, stop and report.
  - In `package.json`, move `@graphprotocol/graph-core` to `dependencies`, because the published sources import it, and remove `@graphprotocol/contracts`. Install.
  - Run `pnpm --filter @graphprotocol/issuance build:self`. Expected:
    - exit 0;
    - in the build-info for RewardsManager, `viaIR` is absent or false, the optimizer is enabled with 200 runs, and the version is 0.8.35;
    - the `deployedBytecode` is under 24,576 bytes.
- [ ] **Step 8: Compare storage layouts.** Run `forge inspect RewardsManager storageLayout --json` in issuance, and pass its output and Step 2's to `compare-storage-layout.mjs`. Expected: exit 0. Commit Step 2's layout as `test/fixtures/pre-port/RewardsManager.storage.json`.
- [ ] **Step 9: Switch the suite to both builds.**
  - Copy Step 2's artifact to `test/fixtures/pre-port/RewardsManager.json`. Add `packages/*/test/fixtures/pre-port/` to `.prettierignore`. Expected: `cmp` against the scratchpad copy prints nothing.
  - Add `_isPrePort` and `_deployPorted` to `ProtocolFixture`, and remove `PKG_ARTIFACTS` and its `fs_permissions` entry. In `shared.t.sol`, deploy with `_deployPorted("RewardsManager.sol:RewardsManager", "test/fixtures/pre-port/RewardsManager.json")`.
  - Set `test:self` to `forge test && PRE_PORT=true forge test --match-path 'test/unit/rewards-manager/**'`.
- [ ] **Step 10: Pin Review Focus 1 and 2** in `build.t.sol`:
  - `test_Build_FoundryMatchesHardhat`: `vm.getCode("RewardsManager.sol:RewardsManager")` equals `.bytecode` of `artifacts/contracts/rewards/RewardsManager.sol/RewardsManager.json`, each with its CBOR metadata tail stripped. It starts with `vm.skip(_isPrePort() || vm.isContext(VmSafe.ForgeContext.Coverage))`.
  - `test_Build_DeploysRequestedBuild`: the code hash of the deployed implementation equals `keccak256` of the fixture's `.deployedBytecode` under `PRE_PORT`, and of `vm.getDeployedCode(id)` otherwise.

  Run `pnpm --filter @graphprotocol/issuance test:self`. Expected: `TBD` passing in each run, 0 failing. Where the builds' revert data differ, the test expects `_isPrePort() ? pre : port`, and the PR lists it.

- [ ] **Step 11: Coverage gate** for `contracts/rewards/RewardsManager.sol`, `contracts/rewards/RewardsManagerStorage.sol` and `contracts/staking/libs/MathUtils.sol`. Run `pnpm --filter @graphprotocol/issuance test:coverage:self`. Expected: exit 0.
- [ ] **Step 12: Repoint consumers.**
  - horizon: change the RewardsManager module import to `@graphprotocol/issuance/artifacts/contracts/rewards/RewardsManager.sol/RewardsManager.json`, and add `@graphprotocol/issuance` as a devDependency.
  - testing:
    - `RM_ARTIFACT` points at issuance's artifact, with an `fs_permissions` entry for `node_modules/@graphprotocol/issuance/artifacts`; remove the `contracts` entry and devDependency.
    - Replace the mock fallback with `require(vm.exists(RM_ARTIFACT), "RewardsManager artifact missing: build issuance")`. Remove `realRmAvailable` and the skip in `IndexingRewardsCollection.t.sol`, and update the harness comment.
  - deployment: set the registry entry to `{ type: 'issuance', path: 'contracts/rewards/RewardsManager.sol/RewardsManager' }`. Load RewardsManager in `bytecode-comparison.test.ts` from issuance with `loadIssuanceArtifact`.
  - Delete the `RewardsManager` entries from `manifest.json` and `reference.json`, and line 10 of `count-patterns.txt`. Change the RewardsManager path in the two REO test plans.
  - Write the changeset. Install.

  Expected:
  - `git grep -n "contracts/rewards/RewardsManager" -- . ':!docs/contracts-removal' ':!**/CHANGELOG.md' ':!scripts/contracts-migration/coverage-baseline.json'` lists only issuance paths.
  - `pnpm --filter @graphprotocol/testing test:self` reports `TBD` passing, 0 skipped.
  - `pnpm --filter @graphprotocol/deployment test:self` passes.

- [ ] **Step 13: Commit.** `refactor(issuance): port RewardsManager to Solidity 0.8`
- [ ] **Step 14: Run the verification block.**

---

### Task Pc: Port L2GNS and L2Curation to subgraph-service

**Files:**

- Move: from `packages/contracts/contracts/` to `packages/subgraph-service/contracts/`, same subpaths: `base/Multicall.sol`, `curation/CurationStorage.sol`, `discovery/{GNS,GNSStorage}.sol`, `l2/curation/L2Curation.sol`, `l2/discovery/{L2GNS,L2GNSStorage}.sol`
- Move: `packages/subgraph-discovery/test/unit/` to `packages/subgraph-service/test/unit/discovery/`, keeping its inner layout; delete the rest of `packages/subgraph-discovery/`
- Create: `packages/subgraph-service/contracts/upgrades/InitializableV3.sol`; `test/fixtures/pre-port/{L2GNS,L2Curation}.json` and `.storage.json`; `test/unit/discovery/Build.t.sol`; `.changeset/subgraph-service-discovery.md` (`@graphprotocol/subgraph-service: minor`)
- Modify: subgraph-service `hardhat.config.ts`, `foundry.toml`, `package.json`, `tasks/deploy.ts`, `ignition/modules/{GNS,Curation}.ts`
- Modify: horizon `ignition/modules/{deploy,index}.ts`, `ignition/modules/periphery/{periphery,Curation,GNS}.ts`, `package.json`, `README.md`; delete `tasks/deploy.ts`
- Modify: deployment `lib/contract-registry.ts:179,205`, `tasks/verify-contract.ts`, `test/bytecode-comparison.test.ts`, `package.json`
- Modify: `scripts/contracts-migration/{manifest,reference}.json`, root `CLAUDE.md`, `pnpm-lock.yaml`

**Interfaces:**

- Consumes:
  - `_isPrePort` and `_deployPorted` (Pb), copied into `test/unit/discovery/shared/ProtocolFixture.t.sol`;
  - `compare-storage-layout.mjs` and the fixture layout from Pb.
- Produces:
  - `buildHorizonModule(artifacts: { L2Curation: Artifact; L2GNS: Artifact })` exported from `@graphprotocol/horizon/ignition`, replacing `HorizonModule`. `Artifact` comes from `@nomicfoundation/ignition-core`.
  - `InitializableV3`: OpenZeppelin 3.4.2's `contracts-upgradeable/proxy/Initializable.sol`, renamed, with `_isConstructor()` returning `address(this).code.length == 0`. The `_initialized`/`_initializing` layout, the `initializer` modifier and its revert string are unchanged.

- [ ] **Step 1: Check in-flight work** for these seven files, as in Pb Step 1.
- [ ] **Step 2: Record the parent commit's outputs** as in Pb Step 2, for `L2GNS` and `L2Curation`: the artifacts, the storage layouts and the fork output. `check:bytecode` prints `OK: 20`.
- [ ] **Step 3: Move.** `git mv` the seven contracts. Expected: seven `R100` lines. Commit `refactor(subgraph-service): move L2GNS and L2Curation from contracts`.
- [ ] **Step 4: Port the seven files** within the allowed changes:
  - `SafeMathUpgradeable` goes.
  - The returns at the old `L2GNS.sol:238` and `:245` go in `unchecked` blocks.
  - `AddressUpgradeable.isContract(x)` becomes `x.code.length > 0` (old `GNS.sol:838`, `L2Curation.sol:469`).
  - `ClonesUpgradeable` becomes OpenZeppelin 5's `Clones`.
  - `CurationStorage` and `GNSStorage` inherit `InitializableV3` instead of `Initializable`.
  - `GNS._buildSubgraphID` goes from `pure` to `view`.

  Add `InitializableV3`.

- [ ] **Step 5: Set the compile config.**
  - `hardhat.config.ts` sets `solidity: { compilers: [baseConfig.solidity], overrides }`, with one entry per moved file plus `contracts/upgrades/InitializableV3.sol`, using the Pb settings.
  - `foundry.toml` pins `contracts/{base,curation,discovery,l2,upgrades}/**` the same way as Pb. It adds `fs_permissions` entries for `node_modules/@graphprotocol/graph-core/artifacts` and `node_modules/@graphprotocol/graph-token/artifacts`.
  - `package.json` removes `@graphprotocol/contracts`. Install.
  - Run `pnpm --filter @graphprotocol/subgraph-service build:self`. Expected: exit 0; the build-info check from Pb Step 7 holds for L2GNS and L2Curation; both `deployedBytecode`s are under 24,576 bytes.
- [ ] **Step 6: Compare storage layouts** for L2GNS and L2Curation, as in Pb Step 8. Expected: exit 0. In L2Curation's layout, `_initialized` is at slot 16.
- [ ] **Step 7: Move the suite and switch it to both builds.**
  - `git mv` the test tree.
  - In `DiscoveryTest.t.sol`, deploy L2Curation and L2GNS with `_deployPorted("L2Curation.sol:L2Curation", "test/fixtures/pre-port/L2Curation.json")` and `_deployPorted("L2GNS.sol:L2GNS", "test/fixtures/pre-port/L2GNS.json")`. Remove `PKG_ARTIFACTS`. Copy the fixtures and check them with `cmp`.
  - Set `test:self` to `forge test && PRE_PORT=true forge test --match-path 'test/unit/discovery/**'`.
  - Delete `packages/subgraph-discovery/`.
- [ ] **Step 8: Pin Review Focus 1 to 4.**
  - `Build.t.sol` has `test_Build_FoundryMatchesHardhat` and `test_Build_DeploysRequestedBuild` for both contracts, as in Pb. The Hardhat artifacts are at `build/contracts/contracts/l2/...`.
  - Add `test_GetUnaliasedL1SubgraphID_WrapsBelowZero`: for `x < OFFSET`, the result is `type(uint256).max - OFFSET + x + 1`.
  - Add `test_L2Curation_InitializedFlagsInSlot16`: after setup, the low two bytes of `vm.load(address(curation), bytes32(uint256(16)))` are `0x0001`, so `_initialized` is true and `_initializing` false. Later variables may pack into the same slot.
  - Add `test_L2Curation_RevertWhen_InitializedTwice` and `test_L2GNS_RevertWhen_InitializedTwice`. Each pranks as the implementation, so `onlyImpl` passes, calls `initialize` on the proxy, and expects `"Initializable: contract is already initialized"`.

  Run `pnpm --filter @graphprotocol/subgraph-service test:self`. Expected: `TBD` passing in each run (`TBD` before the move), 0 failing. Revert-data differences are listed, as in Pb.

- [ ] **Step 9: Coverage gate** for the seven moved files. Run `pnpm --filter @graphprotocol/subgraph-service test:coverage:self`. Expected: exit 0.
- [ ] **Step 10: Pass the artifacts into horizon's modules.**
  - `periphery/Curation.ts` exports `buildCurationModule(artifact)`, and `periphery/GNS.ts` exports `buildGNSModule(artifact, curationModule)`.
  - `periphery.ts` exports `buildPeripheryModule(artifacts)`. It builds the Curation module once and passes that same object to the GNS builder, because Ignition rejects two different modules with the id `L2Curation`.
  - `deploy.ts` exports `buildHorizonModule(artifacts)`, and `index.ts` exports it in place of `HorizonModule`.
  - Delete horizon's `tasks/deploy.ts`, and remove `@graphprotocol/contracts` from horizon. subgraph-service's `tasks/deploy.ts` imports both artifacts from `../build/contracts/contracts/l2/...` and calls `buildHorizonModule`. subgraph-service's `ignition/modules/{GNS,Curation}.ts` import the same paths.
  - Update horizon's README and the root `CLAUDE.md`: `deploy:protocol` runs from subgraph-service only.
  - Run the TypeScript check in horizon and subgraph-service. Run `deploy:protocol`. Expected: the Review Focus 5 checks hold.
- [ ] **Step 11: Update deployment.**
  - Registry entries: `{ type: 'subgraph-service', name: 'l2/curation/L2Curation' }` and `{ type: 'subgraph-service', name: 'l2/discovery/L2GNS' }`.
  - In `verify-contract.ts`, `getFullyQualifiedContractName` uses the basename after `.sol:` for `subgraph-service`. Export it and test that it returns `contracts/l2/curation/L2Curation.sol:L2Curation`.
  - `bytecode-comparison.test.ts` loads L2Curation with `loadSubgraphServiceArtifact`.
  - `build:clean` becomes `pnpm --filter @graphprotocol/issuance --filter @graphprotocol/subgraph-service clean && pnpm build:deps`. Remove `@graphprotocol/contracts` from deployment.

  Run `pnpm --filter @graphprotocol/deployment test:self`. Expected: PASS.

- [ ] **Step 12: Finish.**
  - Delete the `L2GNS` and `L2Curation` entries from `manifest.json` and `reference.json`. Write the changeset. Install.
  - Expected: `git grep -n '"@graphprotocol/contracts"' -- 'packages/*/package.json'` lists only the `name` line in `packages/contracts/package.json`, and `packages/contracts/contracts/` holds only `.gitattributes`.
- [ ] **Step 13: Commit.** `refactor(subgraph-service): port L2GNS and L2Curation to Solidity 0.8`
- [ ] **Step 14: Run the verification block.**

---

### Task 2a: Delete `packages/contracts`

**Files:**

- Delete: `packages/contracts/`
- Modify: deployment `lib/{artifact-loaders,contract-registry,deploy-implementation,deployment-validation}.ts`, `scripts/generate-abis.ts`, `tasks/verify-contract.ts`, `test/bytecode-comparison.test.ts`, `docs/{Design,Architecture}.md`
- Modify: root `CLAUDE.md`, `README.md`, `.gitignore:32,43`, `count-patterns.txt:20`, `.github/workflows/publish.yml` (`contracts` option)
- Modify: `docs/IGraphProxyAdminInterfaceFix.md`, `docs/ForgeLintSymlinkIssue.md`, `docs/Linting.md`, toolshed `src/deployments/{horizon,subgraph-service}/contracts.ts` comments
- Modify: `pnpm-lock.yaml`

- [ ] **Step 1: Record the fork output on the parent commit.**
- [ ] **Step 2: List every remaining reference.** Run `git grep -nE "@graphprotocol/contracts\b|packages/contracts\b" -- . ':!packages/contracts' ':!docs/contracts-removal' ':!**/CHANGELOG.md' ':!pnpm-lock.yaml' ':!packages/legacy/verified' ':!scripts/contracts-migration/test-mapping' | grep -v contracts-monorepo`. Expected: only the files listed above. Report anything else before continuing.
- [ ] **Step 3: Delete the package and its loader support.**
  - Remove `'contracts'` from `ContractsPackage` and `ArtifactSource`, and delete `loadContractsArtifact` and every `case 'contracts'`.
  - Make `ImplementationDeployConfig.artifact` required and delete the `artifactPath` fallback in `deployImplementation`. No caller uses it.
  - Rename the `loadContractsArtifact` describe block in `bytecode-comparison.test.ts` to test `loadPackageArtifact`.
- [ ] **Step 4: Update the references.**
  - Root `CLAUDE.md`: drop the `contracts` package entry and its test command.
  - Docs that use `packages/contracts` as an example now use graph-core.
  - Toolshed comments name the package that now owns each contract.
- [ ] **Step 5: Install and check the lockfile.** Expected: it drops the `packages/contracts` importer and its exclusive dependencies, and changes no remaining importer's solc, OpenZeppelin, Hardhat or forge-std version.
- [ ] **Step 6: Final search.** Run the design's final check: `git grep -n '@graphprotocol/contracts' -- . ':!pnpm-lock.yaml' ':!**/CHANGELOG.md' ':!docs/contracts-removal' ':!scripts/contracts-migration/test-mapping' ':!packages/legacy/verified' | grep -v contracts-monorepo`. Expected: prints nothing.
- [ ] **Step 7: Commit.** `chore: remove packages/contracts`
- [ ] **Step 8: Run the verification block.**

---

### Task 2b: Deprecate the npm packages

Manual, done by the user once 2a is on main after the audit:

```bash
npm deprecate @graphprotocol/contracts "No longer maintained. ABIs: @graphprotocol/interfaces. Addresses: @graphprotocol/address-book."
npm deprecate @graphprotocol/sdk "No longer maintained. Use @graphprotocol/toolshed."
```
