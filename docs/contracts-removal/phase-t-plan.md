# Contracts Removal — Phase T (Foundry Test Ports) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite every live `contracts-test` unit test as a Foundry test in the package that will own the contract, and delete the TypeScript originals. The tests run against the `@graphprotocol/contracts` artifacts, so no contract moves yet.

**Architecture:**

- Each destination package gets a copy of `ProtocolFixture`, a small test base contract. It deploys 0.7.6 contracts from Hardhat JSON artifacts, sets up Controller and GraphProxyAdmin, and puts contracts behind a GraphProxy.
- Tests are Solidity 0.8 and reach the contracts through 0.8-compilable interfaces.
- Every dependency that isn't under test is a mock.
- Artifact paths are always built from two constants, `CORE_ARTIFACTS` (Controller, GraphProxy, GraphProxyAdmin) and `PKG_ARTIFACTS` (the package's own contracts and mocks). In Phase T both point at `@graphprotocol/contracts`. Phase 1 repoints them, and in graph-core, graph-token and subgraph-discovery switches `_deployArtifact` to `deployCode`. The test bodies don't change.

**Tech Stack:** Foundry 1.8.3 (CI's version: `foundryup -i 1.8.3`), forge-std 1.14, solc 0.8.35, pnpm workspaces, Hardhat 2 artifacts from `packages/contracts`, Node 24 (T0 script).

**Spec:** `docs/contracts-removal/design.md`:

- §4 "Tests" (test rules, shared fixture, test assignment, mocks);
- "PR sequence → Phase T";
- "Verification → Test-port PRs".

The executors read the spec and this plan together.

## Global Constraints

### Branching

- Base branch: `chore/contracts-removal-phase-0` (draft PR #1373). Nothing merges to `main` until the audit.
- Every task branches off the current tip of that branch, and its PR targets it: `gh pr create --draft --base chore/contracts-removal-phase-0`.
- The spec and plans are on branch `docs/contracts-package-removal-spec` (PR #1372), not on the base branch. Read them from the main checkout at `~/dev/the-graph/contracts`.
- One PR per task. Branch names are `test/contracts-removal-<id>`, where `<id>` is one of:
  - `t0-coverage-functions`
  - `t1-graph-core`
  - `t2a-graph-token`, `t2b-gateways`
  - `t3a-l2-curation`, `t3b-l2-gns`
  - `t4-epochs`
  - `t5a-rewards-config`, `t5b-rewards-distribution`, `t5c-rewards-issuers`, `t5d-rewards-eligibility`, `t5e-rewards-accounting`, `t5f-rewards-legacy-suite`
- Order:
  1. T0, then T1.
  2. T2a, T3a, T4 and T5a in parallel.
  3. T2b after T2a. T3b after T3a. T5b–T5e after T5a; they can run in parallel with each other.
  4. T5f after T5b–T5e.
- When a sibling PR lands first, rebase onto the new base. For a `pnpm-lock.yaml` conflict:

  ```bash
  git checkout origin/chore/contracts-removal-phase-0 -- pnpm-lock.yaml && pnpm install && git add pnpm-lock.yaml
  ```

### Commits and PRs

- Conventional commits (`test:`, `chore:`). Do NOT add `Co-Authored-By` lines, and do not add any Claude or "Generated with" attribution to commits or PR bodies.
- Run `pnpm install` after any `package.json` change and commit `pnpm-lock.yaml`.

### Scope

- No production contract changes. The only changes to `packages/contracts` in this phase are two test mocks under `contracts/tests/`: `ManagedMock` (T1) and `TokenUtilsMock` (T2a).
- `pnpm check:bytecode` must still print `OK: 26 contracts match`.
- New packages (`graph-core`, `graph-token`, `subgraph-discovery`) are `"private": true` and `"version": "0.0.0"`. Phase 1 makes them publishable.
- They have no Hardhat config yet (nothing to compile). Their Foundry `src` is `test`. This deviates from the spec's Phase T skeleton list: the Hardhat config arrives in Phase 1 with the contracts.
- New packages have no `test:coverage:self`. Foundry can't measure coverage of artifact-deployed bytecode. Coverage is measured in Phase 1.

### Test-file rules (all tasks)

- **Header.** `// SPDX-License-Identifier: MIT` and `pragma solidity ^0.8.27;`, the same as the horizon and issuance tests.
- **No 0.7-only imports.** Never import 0.7-only source. Deploy contracts under test only through `_deployArtifact`.
- **Imports in graph-token and subgraph-discovery:**
  - Test files never import `@openzeppelin/*`, or any `@graphprotocol/interfaces` file that imports `@openzeppelin/*` (`IGraphToken`, `ISubgraphNFT`, `IGraphCurationToken`).
  - They use the local interfaces under `test/unit/interfaces/`.
  - Allowed `@graphprotocol/interfaces` files:
    - `contracts/contracts/governance/{IController,IGoverned,IManaged}.sol`
    - `contracts/contracts/upgrades/{IGraphProxy,IGraphProxyAdmin}.sol`
    - `contracts/contracts/arbitrum/{ITokenGateway,IBridge,IInbox,IOutbox}.sol`
    - `contracts/contracts/gateway/ICallhookReceiver.sol`
  - These packages don't depend on OpenZeppelin, so a violation fails to compile.
- **Naming:**
  - Test functions are `test_<Area>_<Behavior>` and `test_<Area>_RevertWhen_<Condition>`, where `<Area>` is the old `describe` name in PascalCase.
  - The test contract is named after its file (`Controller.t.sol` → `ControllerTest`).
  - Shared setup lives in `shared.t.sol` or `shared/`.
- **Translating a TS test:**
  - Each `it` becomes one test function with the same assertions.
  - `revertedWith("X")` becomes `vm.expectRevert(bytes("X"))`. A bare `.reverted` becomes `vm.expectRevert()`.
  - `vm.expectRevert` must come right before an external call. To expect a revert from an internal helper, call it through an external wrapper (`this.wrapper(...)`).
  - `emit(...).withArgs(...)` becomes `vm.expectEmit(address(target))` plus a locally declared event with the same signature. `not.emit` becomes `vm.recordLogs` plus an assertion that the event's topic is absent.
  - `beforeEach` becomes `setUp` or a modifier. Snapshot and restore are dropped, because Foundry isolates each test.
- **Blocks and time:**
  - Hardhat mines a block per transaction. Foundry runs a whole test in one block until `vm.roll`.
  - Every `helpers.mine`, `mineUpTo` or `mineEpoch` becomes an explicit `vm.roll`.
  - Hand-counted block totals in the old tests are replaced by values computed from the explicit rolls.
  - Every `setUp` calls `vm.warp(1_700_000_000)`. Foundry's default timestamp is 1, which defeats deadline checks.
- **Accounts.** Use `makeAddr` / `makeAddrAndKey`. Random values in the old tests become fixed values, or fuzz parameters where the old test was explicitly randomized.
- **Tolerances.** Keep each old tolerance (`assertApproxEqAbs` / `assertApproxEqRel`). Where Foundry makes a value exact, assert it exactly.
- **No new behaviour tests,** except the ones this plan names and the coverage additions.
- **Formatting.** All Solidity in this plan is shown unformatted. Files are formatted by the repo's prettier (4 spaces, double quotes), and "copy verbatim" means copy the formatted file.

### Mapping tables

- Each port PR adds `scripts/contracts-migration/test-mapping/<task-id>.md` (for example `t2a.md`). Phase 2a deletes the folder with the other migration helpers.
- The table has one row per deleted `it`, with columns `Old file | Old test (describe › it) | New test (file::function) | Note`.
  - `Old file` is the repo-relative path. `New test` is `test/unit/.../<File>.t.sol::<function>`, relative to the package.
  - A dropped test says `dropped: <reason>`. A duplicate points at the test that already covers it.
  - T3b may map all of `gns.test.ts` in one `dropped` row, with the note `88 cases, L1GNS`.
- The file ends with a `## Coverage` section (see the checklist below).
- **Checks** (run them in every port PR):

  ```bash
  BASE=origin/chore/contracts-removal-phase-0
  MAP=scripts/contracts-migration/test-mapping/<task-id>.md
  # 1. cases in the deleted files (repo-relative paths)
  for f in <deleted files>; do git show "$BASE:$f" | grep -cE '\bit(\.only|\.skip)?\('; done
  # 2. rows in the table
  grep -c '^| packages/contracts-test' "$MAP"
  # 3. every referenced test function exists
  grep -oE '[A-Za-z0-9_/.-]+\.t\.sol::[A-Za-z0-9_]+' "$MAP" | while IFS=: read -r file _ fn; do grep -q "function $fn(" "packages/<pkg>/$file" || echo "MISSING $file::$fn"; done
  ```

  Expected: check 1 sums to the PR's case count (in each task), check 2 matches it (T3b: 35 + 1), and check 3 prints nothing.

### Coverage checklist

- After T0, `coverage-baseline.json` lists, per contract, the functions the old suite executed (`functionsHit`).
- **Rule.** Every listed external or public function of the contracts a PR owns is called directly by at least one new test. Internal functions and modifiers in the list count as covered when a test reaches them through a public path.
- The list is a floor. It undercounts: some old tests deployed uninstrumented sdk artifacts. The mapping table is the real completeness guard.
- Print the list, and the external/public names no test mentions yet:

  ```bash
  node -e 'const b=require("./scripts/contracts-migration/coverage-baseline.json");for(const k of process.argv.slice(1))console.log(k, b[k].functionsHit.join(" "))' <keys>
  for fn in <external/public names from the list>; do grep -rqE "\.$fn\(" packages/<pkg>/test || echo "MISSING $fn"; done
  ```

- The `## Coverage` section of the mapping file lists every `MISSING` name with a reason (for example: only reached through a dropped legacy contract). An empty section means none.

## Shared fixture (`test/unit/shared/ProtocolFixture.t.sol` in each package)

Exact API. T1 writes it. T2a, T3a, T4 and T5a copy it verbatim.

```solidity
abstract contract ProtocolFixture is Test {
  string internal constant CORE_ARTIFACTS = 'node_modules/@graphprotocol/contracts/artifacts/contracts/';
  string internal constant PKG_ARTIFACTS = 'node_modules/@graphprotocol/contracts/artifacts/contracts/';

  address internal governor; // makeAddr("governor"), set in _deployProtocolBase
  IController internal controller; // @graphprotocol/interfaces/contracts/contracts/governance/IController.sol
  IGraphProxyAdmin internal proxyAdmin; // @graphprotocol/interfaces/contracts/contracts/upgrades/IGraphProxyAdmin.sol

  /// path is a full artifact path, e.g. string.concat(CORE_ARTIFACTS, "governance/Controller.sol/Controller.json").
  /// Deploys `.bytecode ++ args` with CREATE (honours an active vm.prank).
  /// Reverts "artifact needs linking" if `.linkReferences` has any key (vm.parseJsonKeys),
  /// and "artifact deploy failed" if CREATE returns 0.
  function _deployArtifact(string memory path, bytes memory args) internal returns (address);

  /// As governor: deploys Controller and GraphProxyAdmin from CORE_ARTIFACTS, then controller.setPaused(false).
  /// Must be called with no active prank.
  function _deployProtocolBase() internal;

  /// As governor: deploys GraphProxy(address(0), proxyAdmin) from CORE_ARTIFACTS,
  /// proxyAdmin.upgrade(proxy, impl), proxyAdmin.acceptProxyAndCall(impl, proxy, initData).
  /// Must be called with no active prank.
  function _deployBehindProxy(address impl, bytes memory initData) internal returns (address proxy);

  /// As governor: controller.setContractProxy(keccak256(bytes(name)), addr).
  function _registerContract(string memory name, address addr) internal;
}
```

Each `foundry.toml` gets an explicit read permission for the artifact folder. pnpm symlinks point outside the package, so `"./"` does not cover them:

```toml
fs_permissions = [{ access = "read", path = "node_modules/@graphprotocol/contracts/artifacts" }]
```

(Existing packages add it to their current `fs_permissions` list.)

### Shared local token interface (`test/unit/interfaces/IGraphTokenLike.sol`, T2a and T3a)

Both packages write the same file, from this list, so they don't depend on each other:

- ERC20: `totalSupply`, `balanceOf`, `transfer`, `transferFrom`, `approve`, `allowance`, and the `Transfer` and `Approval` events.
- Burning: `burn(uint256)`, `burnFrom(address,uint256)`.
- Minting: `mint(address,uint256)`, `addMinter`, `removeMinter`, `renounceMinter`, `isMinter`, and the `MinterAdded(address indexed)` and `MinterRemoved(address indexed)` events.
- Permit: `permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)`, `nonces(address)`.
- Governance: `governor()`, `transferOwnership`, `acceptOwnership`.

The domain separator is private in both tokens. Tests compute it locally (see T2a).

## Review Focus

1. **Missing or stale artifact.** A missing artifact must fail loudly. It must never skip, and never fall back to a mock (the `RealRewardsHarness` fallback is the anti-pattern). A missing `fs_permissions` entry also makes reads revert, which must not pass for a missing-file test.
   - → T1 `test_Fixture_ArtifactReadable`: `assertTrue(vm.isFile(<Controller artifact>))`.
   - → T1 `test_Fixture_RevertWhen_ArtifactMissing`: an external wrapper around `_deployArtifact` on a nonexistent path, expecting a revert.
2. **Constructor or initializer wiring silently wrong.** GraphProxy args are appended in the wrong order, or the implementation is never accepted, so calls hit a proxy with no implementation.
   - → T1 `test_Fixture_ProxyWiredToImplementation` asserts `getProxyAdmin(proxy) == proxyAdmin`, `getProxyImplementation(proxy) == impl` and `getProxyPendingImplementation(proxy) == address(0)`.
3. **Controller left paused.** The Controller constructor pauses the protocol. Any `notPaused` path would then revert with "Paused" and mask the behaviour under test.
   - → T1 `test_Fixture_ControllerUnpaused`.
4. **Same-block semantics.** A port that forgets `vm.roll` asserts zero accrual where the old test expected per-block accrual, or the reverse. Fails silently if the expected value is copied from the TS test instead of derived from the rolls.
   - → T4 `test_EpochManager_SameBlockDoesNotAdvance`.
   - → T5b `test_Rewards_ZeroWhenNoBlocksElapsed`: two calls with no roll in between return an equal `accRewardsPerSignal`.
5. **Default timestamp of 1.** A deadline of 1 is not expired in Foundry, so an "expired permit" test passes for the wrong reason.
   - → T2a `test_Permit_RevertWhen_Expired` warps to `1_700_000_000` and uses `deadline = block.timestamp - 1`.

---

### Task 0 (PR T0): Record covered functions in the coverage baseline

**Files:**

- Modify: `scripts/contracts-migration/summarize-coverage.mjs`
- Modify: `scripts/contracts-migration/summarize-coverage.test.mjs`
- Modify: `scripts/contracts-migration/coverage-baseline.json` (regenerated)

**Interfaces:**

- Consumes: nothing.
- Produces: `parseLcov(text)` returns `{ [key]: { linesFound, linesHit, pct, functionsHit: string[] } }`.
  - `functionsHit` is sorted and de-duplicated.
  - Empty names are left out (solidity-coverage gives fallback and receive an empty name).
  - Every later task reads `functionsHit`.

The current `parseLcov` reads `LF`/`LH` and overwrites repeated `SF:` records for the same key. The new one computes from `DA:` and `FNDA:` records and merges duplicates:

- a line counts as found if any record has it;
- it counts as hit if any record hit it;
- functions are the union of `FNDA:<n>,<name>` with `n > 0`.

`LF`/`LH` records are ignored.

- [ ] **Step 1: Write failing tests** in `summarize-coverage.test.mjs`. Keep the existing tests.

  ```js
  test('computes lines from DA records', ...)            // DA:1,3 DA:2,0 DA:3,1 → linesFound 3, linesHit 2, pct 66.67
  test('merges duplicate SF records', ...)               // same SF twice: {DA:1,0 DA:2,1} and {DA:1,2 DA:3,0} → found 3, hit 2
  test('lists hit functions sorted and unique', ...)     // FNDA:2,b FNDA:0,c FNDA:1,a (+ dup record FNDA:1,b) → ['a','b']
  test('drops empty function names', ...)                // FNDA:1, (empty name) → []
  test('file without functions has empty functionsHit', ...)
  ```

- [ ] **Step 2: Run** `pnpm test:scripts`. Expected: the new tests fail.
- [ ] **Step 3: Implement** the new `parseLcov` (same exported name and signature). `main` is unchanged.
- [ ] **Step 4: Run** `pnpm test:scripts`. Expected: all pass.
- [ ] **Step 5: Regenerate the baseline** from the unmodified suite on this branch. solidity-coverage writes `packages/coverage/lcov.info` (`istanbulFolder: '../coverage'`).

  ```bash
  pnpm build && pnpm --filter @graphprotocol/contracts-tests test:coverage:self
  node scripts/contracts-migration/summarize-coverage.mjs packages/coverage/lcov.info scripts/contracts-migration/coverage-baseline.json
  ```

  Expected: `git diff` only adds `functionsHit` arrays. `linesFound` and `linesHit` stay the same for every key, except keys that had duplicate `SF:` records.
  - If anything else changes, stop and report the keys.
  - If duplicates changed a value, keep the merged value and list those keys in the PR body.

- [ ] **Step 6: Commit and open the PR.**

  ```bash
  git commit -am "test: record covered functions in the contracts-test coverage baseline"
  ```

---

### Task 1 (PR T1): graph-core package and governance/upgrade tests

**Cases:** 36 (`governed` 2, `controller` 12, `pausing` 8, `admin` 14).

**Files:**

- Create:
  - `packages/graph-core/package.json`
  - `packages/graph-core/foundry.toml`
- Create, under `packages/graph-core/test/unit/`:
  - `shared/ProtocolFixture.t.sol`
  - `shared/GraphCoreTest.t.sol` (base: `_deployProtocolBase` plus a `ManagedMock` behind a proxy)
  - `shared/Fixture.t.sol` (Review Focus 1–3)
  - `interfaces/IManagedMock.sol`
  - `governance/Governed.t.sol`
  - `governance/Controller.t.sol`
  - `governance/Managed.t.sol`
  - `governance/Pausing.t.sol`
  - `upgrades/GraphProxyAdmin.t.sol`
  - `upgrades/GraphProxy.t.sol`
- Create: `packages/contracts/contracts/tests/ManagedMock.sol`
- Create: `scripts/contracts-migration/test-mapping/t1.md`
- Delete, under `packages/contracts-test/tests/unit/`:
  - `governance/governed.test.ts`
  - `governance/controller.test.ts`
  - `governance/pausing.test.ts`
  - `upgrade/admin.test.ts`
- Modify: `pnpm-lock.yaml`

**Interfaces:**

- Consumes: T0 `functionsHit`.
- Produces:
  - the `ProtocolFixture` API above;
  - `ManagedMock` at `PKG_ARTIFACTS + "tests/ManagedMock.sol/ManagedMock.json"`;
  - the `package.json` and `foundry.toml` templates, which T2a and T3a copy, changing only the name, description and devDependencies.

`package.json`:

```json
{
  "name": "@graphprotocol/graph-core",
  "version": "0.0.0",
  "private": true,
  "description": "The Graph governance and proxy contracts",
  "license": "GPL-2.0-or-later",
  "scripts": {
    "build": "pnpm build:dep",
    "build:dep": "pnpm --filter '@graphprotocol/graph-core^...' run build:self",
    "clean": "rm -rf forge-artifacts/ cache_forge/",
    "test": "pnpm build && pnpm test:self",
    "test:self": "forge test"
  },
  "devDependencies": {
    "@graphprotocol/contracts": "workspace:^",
    "@graphprotocol/interfaces": "workspace:^",
    "forge-std": "catalog:"
  }
}
```

`foundry.toml`:

- Same as `packages/testing/foundry.toml`, except:
  - `src = 'test'`
  - `auto_detect_remappings = false`
  - remappings `@graphprotocol/=node_modules/@graphprotocol/` and `forge-std/=node_modules/forge-std/src/` only
  - the `fs_permissions` line above
  - `ignored_warnings_from = ["node_modules"]`
- Keep `solc_version = '0.8.35'`, `evm_version = 'cancun'` and the `[lint]` block.
- No `[profile.prod]`.

`ManagedMock.sol` (0.7.6, in `contracts/tests/` next to `GovernedMock.sol`):

- Header: the SPDX line, `pragma solidity ^0.7.6;` and `// solhint-disable use-natspec`.
- No `TODO` line: `pnpm todo` (part of `lint:sol`) fails on it.

```solidity
contract ManagedMock is Managed, GraphUpgradeable {
  function initialize(address _controller) external onlyImpl {
    Managed._initialize(_controller);
  }
  function checkNotPartialPaused() external view notPartialPaused {}
  function checkNotPaused() external view notPaused {}
  function checkOnlyGovernor() external view onlyGovernor {}
  /// curation, epochManager, rewardsManager, staking, graphToken, graphTokenGateway, gns — in that order
  function resolveAll() external view returns (address[7] memory);
}
```

It replaces the EpochManager, Staking and Curation contracts the old tests used as "some Managed / some GraphUpgradeable contract" (spec §4 notes). Phase 1 moves it to graph-core with `GovernedMock`.

- [ ] **Step 1: Write the fixture and its tests.** Write `ProtocolFixture`, `IManagedMock`, `GraphCoreTest` and `shared/Fixture.t.sol` (the four Review Focus 1–3 tests).
  - `GraphCoreTest.setUp`: `vm.warp(1_700_000_000)`, `_deployProtocolBase()`, then two `ManagedMock` implementations (`implA`, `implB`).
  - `managed = IManagedMock(_deployBehindProxy(implA, abi.encodeCall(IManagedMock.initialize, (address(controller)))))`.
- [ ] **Step 2: Run** `pnpm --filter @graphprotocol/graph-core test`. Expected: the build succeeds and the four fixture tests pass.
- [ ] **Step 3: Port the four TS files.** Old → new:

  | Old                                          | New                                                                                                                                                                                                                                     |
  | -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
  | `governed.test.ts`                           | `governance/Governed.t.sol`. Deploys `PKG_ARTIFACTS + "tests/GovernedMock.sol/GovernedMock.json"` as governor.                                                                                                                          |
  | `controller.test.ts` (`describe('Managed')`) | `governance/Controller.t.sol`. `setUp` registers the `ManagedMock` proxy under the `EpochManager` id. Without it, `updateController` calls address zero. `setController` is called directly on the proxy.                               |
  | `pausing.test.ts`                            | `governance/Pausing.t.sol`. "fails when partialPause is set": `checkNotPartialPaused` reverts `Partial-paused`. "fails when pause is set": `checkNotPartialPaused` and `checkNotPaused` both revert `Paused`.                           |
  | `admin.test.ts`                              | `upgrades/GraphProxyAdmin.t.sol`. "Staking proxy" becomes the `ManagedMock` proxy, and "Curation implementation" becomes `implB`. Reading `implementation()` / `admin()` / `pendingImplementation()` directly from a non-admin reverts. |

- [ ] **Step 4: Cover the checklist.** Run the checklist commands for:
  - `contracts/governance/Controller.sol`
  - `contracts/governance/Governed.sol`
  - `contracts/governance/Managed.sol`
  - `contracts/governance/Pausable.sol`
  - `contracts/upgrades/GraphProxy.sol`
  - `contracts/upgrades/GraphProxyAdmin.sol`
  - `contracts/upgrades/GraphProxyStorage.sol`
  - `contracts/upgrades/GraphUpgradeable.sol`

  Add a test for every `MISSING` name. Expected additions:
  - `Managed.t.sol`:
    - `syncAllContracts` emits `ContractSynced` per changed id, and nothing on a second call;
    - `resolveAll` returns the controller's addresses before the sync and the cached addresses after it;
    - `checkOnlyGovernor` reverts `Only Controller governor`.
  - `GraphProxy.t.sol`:
    - `acceptUpgradeAndCall` reverts `Impl call failed` on failing calldata;
    - the admin calling the fallback reverts `Cannot fallback to proxy target`;
    - `setAdmin(0)` reverts `Admin cant be the zero address`;
    - `acceptUpgrade` with `vm.prank(address(proxyAdmin))` and no pending implementation reverts `Impl cannot be zero address`;
    - from a non-pending implementation, it reverts `Only pending implementation`.
  - `Governed.t.sol`: `transferOwnership(0)` reverts `Governor must be set`.

- [ ] **Step 5: Run** `pnpm --filter @graphprotocol/graph-core test` and `pnpm --filter @graphprotocol/contracts-tests test:self`. Expected: all pass.
- [ ] **Step 6: Lint and check bytecode.** Run:
  - `pnpm check:bytecode` (expect `OK: 26 contracts match`);
  - `(cd packages/contracts && npx solhint --max-warnings=0 contracts/tests/ManagedMock.sol)` (expect exit 0);
  - `pnpm lint:sol && git status --short` (expect exit 0 and no files changed; commit any formatting fixes first).
- [ ] **Step 7:** Write `t1.md` and run the mapping checks. Expected: 36 cases, 36 rows, no `MISSING`.
- [ ] **Step 8: Commit and open the PR.**

  ```bash
  git commit -m "test(graph-core): port governance and proxy tests to Foundry"
  ```

---

### Task 2a (PR T2a): graph-token package, tokens, BridgeEscrow and TokenUtils

**Cases:** 30 (`lib/graphTokenTests.ts` 15, `l2/l2GraphToken.test.ts` 11, `gateway/bridgeEscrow.test.ts` 4, `graphToken.test.ts` 0).

**Files:**

- Create:
  - `packages/graph-token/package.json`
  - `packages/graph-token/foundry.toml`
- Create, under `packages/graph-token/test/unit/`:
  - `shared/ProtocolFixture.t.sol` (copy of T1's)
  - `interfaces/IGraphTokenLike.sol` (shared list above)
  - `interfaces/IL2GraphTokenLike.sol`
  - `interfaces/IBridgeEscrowLike.sol`
  - `interfaces/ITokenUtilsMock.sol`
  - `token/GraphTokenShared.t.sol` (abstract)
  - `token/GraphToken.t.sol`
  - `token/L2GraphToken.t.sol`
  - `gateway/BridgeEscrow.t.sol`
  - `utils/TokenUtils.t.sol`
- Create: `packages/contracts/contracts/tests/TokenUtilsMock.sol`
- Create: `scripts/contracts-migration/test-mapping/t2a.md`
- Delete, under `packages/contracts-test/tests/unit/`:
  - `graphToken.test.ts`
  - `lib/graphTokenTests.ts`
  - `l2/l2GraphToken.test.ts`
  - `gateway/bridgeEscrow.test.ts`

**Interfaces:**

- Consumes: `ProtocolFixture`.
- Produces: the graph-token package with `ProtocolFixture` and `IGraphTokenLike`, which T2b uses.
- devDependencies: `@graphprotocol/contracts`, `@graphprotocol/interfaces`, `forge-std`. No OpenZeppelin.
- `IL2GraphTokenLike is IGraphTokenLike`, adding:
  - `initialize(address)`, `gateway()`, `l1Address()`, `setGateway`, `setL1Address`, `bridgeMint`, `bridgeBurn`;
  - the `GatewaySet`, `L1AddressSet`, `BridgeMinted` and `BridgeBurned` events, with the contract's signatures.
- `IBridgeEscrowLike`: `initialize(address)`, `approveAll(address)`, `revokeAll(address)`.
- `TokenUtilsMock.sol` (0.7.6, in `contracts/tests/`, same header rules as `ManagedMock`):

  ```solidity
  contract TokenUtilsMock {
    function pullTokens(IGraphToken token, address from, uint256 amount) external {
      TokenUtils.pullTokens(token, from, amount);
    }
    function pushTokens(IGraphToken token, address to, uint256 amount) external {
      TokenUtils.pushTokens(token, to, amount);
    }
    function burnTokens(IGraphToken token, uint256 amount) external {
      TokenUtils.burnTokens(token, amount);
    }
  }
  ```

  - In the live code, TokenUtils is only used by GNS and L2Curation, which aren't in graph-token. Without this mock, graph-token can't reach TokenUtils' baseline coverage in Phase 1.
  - Phase 1 moves the mock to graph-token with TokenUtils.

**Artifacts and setup** (`PKG_ARTIFACTS` +):

| Contract       | Path                                           |
| -------------- | ---------------------------------------------- |
| GraphToken     | `token/GraphToken.sol/GraphToken.json`         |
| L2GraphToken   | `l2/token/L2GraphToken.sol/L2GraphToken.json`  |
| BridgeEscrow   | `gateway/BridgeEscrow.sol/BridgeEscrow.json`   |
| TokenUtilsMock | `tests/TokenUtilsMock.sol/TokenUtilsMock.json` |

- **GraphToken** is not proxied: deploy as governor with `abi.encode(10_000_000_000 ether)`.
- **L2GraphToken** is behind a proxy: `initialize(governor)`.
- **BridgeEscrow** is behind a proxy: `initialize(controller)`. Register `GraphToken` in the controller first, then call `syncAllContracts()`.
- **`GraphTokenSharedTest`** carries every `lib/graphTokenTests.ts` case once:
  - abstract hooks `_token() returns (IGraphTokenLike)` and `_salt() returns (bytes32)`;
  - L1 salt `0x51f3d585afe6dfeb2af01bba0889a36c1db03beec88c6a4d0c53817069026afa`;
  - L2 salt `0xe33842a7acd1d5a1d28f25a931703e5605152dc48d64dc4716efdae1f5659591`;
  - `_domainSeparator()` computes `keccak256(abi.encode(keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"), keccak256("Graph Token"), keccak256("0"), block.chainid, address(_token()), _salt()))`;
  - the permit digest is `keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), keccak256(abi.encode(keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"), owner, spender, value, nonce, deadline))))`;
  - permits are signed with `vm.sign` using the key from `makeAddrAndKey("me")`;
  - `GraphToken.t.sol` and `L2GraphToken.t.sol` inherit it. The L2 file also holds the "Extended L2 behavior" cases, with the gateway and L1 address as plain `makeAddr` accounts.
- **`TokenUtils.t.sol`**:
  - `pullTokens` moves tokens from an approved holder to the mock;
  - `pullTokens` and `pushTokens` with amount 0 do nothing;
  - `pushTokens` moves tokens from the mock;
  - `burnTokens` lowers `totalSupply`.

Steps:

- [ ] **Step 1: Scaffold.** Write the package, copy `ProtocolFixture`, and write the interfaces and `GraphTokenSharedTest`, including Review Focus 5.
- [ ] **Step 2: Run** `pnpm --filter @graphprotocol/graph-token test`. Expected: the shared tests pass for both tokens.
- [ ] **Step 3: Port** the L2 extensions and BridgeEscrow. Write `TokenUtilsMock` and `TokenUtils.t.sol`. Run the package tests after each file. Expected: pass.
- [ ] **Step 4: Cover the checklist** for:
  - `contracts/token/GraphToken.sol`
  - `contracts/l2/token/L2GraphToken.sol`
  - `contracts/l2/token/GraphTokenUpgradeable.sol`
  - `contracts/gateway/BridgeEscrow.sol`
  - `contracts/utils/TokenUtils.sol`
- [ ] **Step 5: Run** the package tests, `pnpm --filter @graphprotocol/contracts-tests test:self`, `pnpm check:bytecode`, `(cd packages/contracts && npx solhint --max-warnings=0 contracts/tests/TokenUtilsMock.sol)`, and `pnpm lint:sol && git status --short`. Expected: all pass, and no files changed.
- [ ] **Step 6:** Write `t2a.md` and run the mapping checks. Expected: 30 cases, 30 rows (the two identically titled permit cases are two rows), no `MISSING`.
- [ ] **Step 7: Commit and open the PR.**

  ```bash
  git commit -m "test(graph-token): port token, escrow and token utils tests to Foundry"
  ```

---

### Task 2b (PR T2b): graph-token gateway tests

**Cases:** 74 (`gateway/l1GraphTokenGateway.test.ts` 46, `l2/l2GraphTokenGateway.test.ts` 28).

**Files:**

- Create, under `packages/graph-token/test/unit/`:
  - `interfaces/IL1GraphTokenGatewayLike.sol`
  - `interfaces/IL2GraphTokenGatewayLike.sol`
  - `interfaces/IArbitrumMocksLike.sol`
  - `gateway/L1GraphTokenGatewayShared.t.sol`
  - `gateway/L1GraphTokenGatewayConfig.t.sol`
  - `gateway/L1GraphTokenGatewayTransfers.t.sol`
  - `gateway/L2GraphTokenGatewayShared.t.sol`
  - `gateway/L2GraphTokenGatewayConfig.t.sol`
  - `gateway/L2GraphTokenGatewayTransfers.t.sol`
  - `mocks/NoCallhookReceiver.sol` (an empty 0.8 contract: no fallback, so any call reverts)
- Create: `scripts/contracts-migration/test-mapping/t2b.md`
- Delete, under `packages/contracts-test/tests/unit/`:
  - `gateway/l1GraphTokenGateway.test.ts`
  - `l2/l2GraphTokenGateway.test.ts`
  - `l2/l2ArbitrumMessengerMock.ts` (imported by nothing)

**Interfaces:**

- Consumes: T2a's package, `ProtocolFixture` and `IGraphTokenLike`.
- Produces: nothing for other tasks.
- `IL1GraphTokenGatewayLike`:
  - `initialize(address)`;
  - `setArbitrumAddresses(address inbox, address router)`, `setL2TokenAddress`, `setL2CounterpartAddress`, `setEscrowAddress`;
  - `addToCallhookAllowlist`, `removeFromCallhookAllowlist`, `callhookAllowlist(address)`;
  - `updateL2MintAllowance(uint256 l2IssuancePerBlock, uint256 updateBlockNum)`, `setL2MintAllowanceParametersManual(uint256 accumulatedAllowance, uint256 l2IssuancePerBlock, uint256 lastUpdateBlock)`, `accumulatedL2MintAllowanceAtBlock(uint256)`;
  - getters: `accumulatedL2MintAllowanceSnapshot`, `l2MintAllowancePerBlock`, `lastL2MintAllowanceUpdateBlock`, `totalMintedFromL2`, `l2GRT`, `inbox`, `l1Router`, `l2Counterpart`, `escrow`, `counterpartGateway`, `calculateL2TokenAddress`;
  - pause: `setPaused`, `paused`, `setPauseGuardian`, `pauseGuardian`;
  - transfers: `outboundTransfer` and `finalizeInboundTransfer` with `ITokenGateway`'s signatures;
  - every event the contract declares.
- `IL2GraphTokenGatewayLike`:
  - `initialize(address)`;
  - `setL2Router`, `setL1TokenAddress`, `setL1CounterpartAddress`, their getters, and `calculateL2TokenAddress`;
  - the 4-argument `outboundTransfer(address l1Token, address to, uint256 amount, bytes data)` and the `ITokenGateway` overloads;
  - the same pause functions as L1;
  - every event the contract declares (`DepositFinalized`, `WithdrawalInitiated`, `TxToL1`, `L2RouterSet`, …).
- `IArbitrumMocksLike`:
  - BridgeMock: `setInbox(address,bool)`, `setOutbox(address,bool)`;
  - InboxMock and OutboxMock: `setBridge(address)`;
  - OutboxMock: `executeTransaction(...)`, with the mock's exact parameter list;
  - CallhookReceiverMock: the `TransferReceived(address from, uint256 amount, uint256 foo, uint256 bar)` event.
- Copy exact parameter lists and event signatures from the 0.7.6 sources in `packages/contracts/contracts/`.

**Artifacts and setup** (`PKG_ARTIFACTS` +):

| Contract                          | Path                                                          |
| --------------------------------- | ------------------------------------------------------------- |
| L1GraphTokenGateway               | `gateway/L1GraphTokenGateway.sol/L1GraphTokenGateway.json`    |
| L2GraphTokenGateway               | `l2/gateway/L2GraphTokenGateway.sol/L2GraphTokenGateway.json` |
| BridgeMock, InboxMock, OutboxMock | `tests/arbitrum/<Name>.sol/<Name>.json`                       |
| CallhookReceiverMock              | `tests/CallhookReceiverMock.sol/CallhookReceiverMock.json`    |

- **Gateways:** behind a proxy, `initialize(controller)`. Register `GraphToken` and `GraphTokenGateway`, then call `syncAllContracts()`. Gateways start paused.
- **Counterpart contracts** (the other layer's token and gateway, routers): `makeAddr` plus `vm.etch(addr, hex"1234")`.
- **L1 bridge mocks:**
  - Wiring: `bridge.setInbox(inbox, true)`, `bridge.setOutbox(outbox, true)`, `inbox.setBridge(bridge)`, `outbox.setBridge(bridge)`.
  - Inbound calls go through `outbox.executeTransaction(...)`.
- **ArbSys:** don't use the ArbSysMock artifact. The spec deletes it in D3.
  - `vm.etch(address(0x64), hex"00")` gives the address code, which 0.7.6's extcodesize check needs.
  - `vm.mockCall(address(0x64), abi.encodeWithSignature("sendTxToL1(address,bytes)"), abi.encode(uint256(1)))`.
  - Outbound tests add `vm.expectCall(address(0x64), abi.encodeWithSignature("sendTxToL1(address,bytes)", l1Gateway, data))`.
- **L2 inbound:** `vm.prank(address(uint160(l1Counterpart) + uint160(0x1111000000000000000000000000000000001111)))`, as an unchecked add.
- **"Any contract" for the callhook allowlist:** any deployed address. Replaces RewardsManager.
- **"Contract without onTokenTransfer":** `NoCallhookReceiver`, asserted with a bare `vm.expectRevert()`.
- **Mint allowance test:** derive block numbers from explicit `vm.roll`s. For example: update the allowance at block B, roll to B + 4, then expect an allowance of 8 GRT at 2 GRT per block.

Steps:

- [ ] **Step 1: Write the interfaces and the L1 shared base.** Port the L1 `> immediately after deploy` cases into `L1GraphTokenGatewayConfig.t.sol`. Run `pnpm --filter @graphprotocol/graph-token test`. Expected: pass.
- [ ] **Step 2: Port** the L1 `> after configuring and unpausing` cases into `L1GraphTokenGatewayTransfers.t.sol`. Run the package tests. Expected: pass.
- [ ] **Step 3: Port** the L2 gateway the same way, split into config and transfers. Run the package tests. Expected: pass.
- [ ] **Step 4: Cover the checklist** for:
  - `contracts/gateway/GraphTokenGateway.sol`
  - `contracts/gateway/L1GraphTokenGateway.sol`
  - `contracts/l2/gateway/L2GraphTokenGateway.sol`

  The L2 gateway's baseline lacks `getOutboundCalldata`, because the old test skipped it under coverage. Cover it anyway; it's in the TS test.

- [ ] **Step 5: Run** the package tests, `pnpm --filter @graphprotocol/contracts-tests test:self`, `pnpm check:bytecode` and `pnpm lint:sol && git status --short`. Expected: all pass, and no files changed.
- [ ] **Step 6:** Write `t2b.md` and run the mapping checks. Expected: 74 cases, 74 rows, no `MISSING`.
- [ ] **Step 7: Commit and open the PR.**

  ```bash
  git commit -m "test(graph-token): port gateway tests to Foundry"
  ```

---

### Task 3a (PR T3a): subgraph-discovery package and L2Curation tests

**Cases:** 43 (`l2/l2Curation.test.ts`).

**Files:**

- Create:
  - `packages/subgraph-discovery/package.json` (devDependencies as in T2a)
  - `packages/subgraph-discovery/foundry.toml`
- Create, under `packages/subgraph-discovery/test/unit/`:
  - `shared/ProtocolFixture.t.sol`
  - `shared/DiscoveryTest.t.sol` (full setup below; used by T3b too)
  - `mocks/L2GatewayMock.sol`
  - `interfaces/IGraphTokenLike.sol` (shared list above)
  - `interfaces/IL2GNSLike.sol`
  - `interfaces/IL2CurationLike.sol`
  - `interfaces/ISubgraphNFTLike.sol`
  - `interfaces/IERC20Like.sol` (`balanceOf`, `totalSupply`; for curation-token balances)
  - under `l2-curation/`:
    - `Config.t.sol`
    - `BondingCurve.t.sol`
    - `Curate.t.sol`
    - `CurateTaxFree.t.sol`
    - `Collect.t.sol`
    - `Burn.t.sol`
    - `Conservation.t.sol`
    - `MultipleMinting.t.sol`
- Create: `scripts/contracts-migration/test-mapping/t3a.md`
- Delete: `packages/contracts-test/tests/unit/l2/l2Curation.test.ts`

**Interfaces:**

- Consumes: `ProtocolFixture`.
- Produces, used by T3b:
  - `DiscoveryTest`;
  - `L2GatewayMock`;
  - `IL2GNSLike`, `IL2CurationLike`, `ISubgraphNFTLike`.
- `DiscoveryTest` fields:
  - contracts: `grt` (`IGraphTokenLike`), `curation` (`IL2CurationLike`), `gns` (`IL2GNSLike`), `nft` (`ISubgraphNFTLike`), `gatewayMock`, `curationTokenMaster`;
  - accounts, all from `makeAddr`: `me`, `other`, `curator`, `attacker`, `l1GNS`, `subgraphService`.
- `IL2GNSLike`:
  - the entries of `IGNS` and `IL2GNS` the tests call, both overloads of `publishNewVersion`, and `onTokenTransfer`;
  - `initialize(address,address)`, `approveAll()`, `setCounterpartGNSAddress(address)`, `counterpartGNSAddress()`;
  - `ownerTaxPercentage()`, `setOwnerTaxPercentage(uint32)`, `nextAccountSeqID(address)`;
  - `subgraphs(uint256) returns (uint256 vSignal, uint256 nSignal, bytes32 subgraphDeploymentID, uint32 reserveRatio, bool disabled, uint256 withdrawableGRT)`;
  - `subgraphL2TransferData(uint256) returns (uint256 tokens, bool l2Done, uint256 subgraphReceivedOnL2BlockNumber)`;
  - `getAliasedL2SubgraphID(uint256)`;
  - every event the tests assert.
- `IL2CurationLike`:
  - the entries of `ICuration` the tests call;
  - `initialize(address,address,uint32,uint256)`;
  - `pools(bytes32) returns (uint256 tokens, uint32 reserveRatio, address gcs)`;
  - `defaultReserveRatio()`, `setDefaultReserveRatio(uint32)`;
  - `minimumCurationDeposit()`, `setMinimumCurationDeposit(uint256)`, `setCurationTaxPercentage(uint32)`;
  - `curationTokenMaster()`, `setCurationTokenMaster(address)`;
  - `subgraphService()`, `setSubgraphService(address)`, `collect(bytes32,uint256)`;
  - `mintTaxFree`, `tokensToSignalNoTax`, `tokensToSignalToTokensNoTax`;
  - the `Signalled`, `Burned` and `Collected` events.
- `ISubgraphNFTLike`: `ownerOf`, `setMinter`, `setTokenDescriptor`, `tokenURI`.
- `L2GatewayMock` (0.8):
  - `constructor(address token)`;
  - `function deliver(address gns, address l1From, uint256 amount, bytes calldata data) external`. It calls `IGraphTokenLike(token).mint(gns, amount)` and then `ICallhookReceiver(gns).onTokenTransfer(l1From, amount, data)`. Mint first, then forward, like `L2GraphTokenGateway.finalizeInboundTransfer`.

**`DiscoveryTest.setUp`** (spec §4 "L2GNS" and "L2Curation" setup), all artifacts from `PKG_ARTIFACTS`:

1. `vm.warp(1_700_000_000)`, then `_deployProtocolBase()`.
2. L2GraphToken behind a proxy (`initialize(governor)`). As governor, `addMinter(gatewayMock)` and `addMinter(governor)`.
3. GraphCurationToken master (`curation/GraphCurationToken.sol/GraphCurationToken.json`, deployed uninitialized).
4. L2Curation behind a proxy: `initialize(controller, curationTokenMaster, 0, 1)`.
5. SubgraphNFT (`discovery/SubgraphNFT.sol/SubgraphNFT.json`, `abi.encode(governor)`). Deploy SubgraphNFTDescriptor (`discovery/SubgraphNFTDescriptor.sol/SubgraphNFTDescriptor.json`) and set it with `setTokenDescriptor`.
6. L2GNS behind a proxy: `initialize(controller, nft)`. `nft.setMinter(gns)`.
7. Register `GraphToken`, `Curation`, `GNS` and `GraphTokenGateway` (= `gatewayMock`), then call `syncAllContracts()` on curation and GNS.
8. `gns.approveAll()`, `gns.setCounterpartGNSAddress(l1GNS)`, `curation.setSubgraphService(subgraphService)`.

- There is no staking, rewards manager or epoch manager. L2Curation skips the rewards hook when RewardsManager resolves to zero (`L2Curation.sol` `_updateRewards`).
- Tests that need curation as the caller use `vm.prank(address(gns))` (it replaces the old impersonation of the GNS proxy). Tests that need curator funds mint as governor.

Steps:

- [ ] **Step 1: Scaffold.** Write the package, `DiscoveryTest`, `L2GatewayMock` and the interfaces. Add `test_Setup_Wired`: `nft` minter is `gns`, `curation.subgraphService() == subgraphService`, and `gns.counterpartGNSAddress() == l1GNS`.
- [ ] **Step 2: Run** `pnpm --filter @graphprotocol/subgraph-discovery test`. Expected: pass.
- [ ] **Step 3: Port** `l2Curation.test.ts`, one `describe` block per file, as listed above.
  - `Config.t.sol`: the `L2Curation:Config` describe.
  - `MultipleMinting.t.sol`: the `multiple minting` describe.
  - The leftover `setContractProxy("Staking")` lines in the collect tests are dropped, because `collect` only checks `subgraphService`.
  - `Conservation.t.sol` is pinned as `testFuzz_Conservation_DepositsAndRedeemsMatch(uint256[10] memory depositCuts, uint256[10] memory redeemCuts)`:
    - Split exactly `1_000_000_000 ether` into 10 deposit chunks, cutting at `bound(cut, 0, remaining)`; the last chunk takes the remainder.
    - Skip zero chunks (no call).
    - Split the curator's resulting signal into 10 redeem chunks the same way.
    - Assert that the pool and the curator end with exactly the initial token balances.
- [ ] **Step 4: Cover the checklist** for:
  - `contracts/l2/curation/L2Curation.sol`
  - `contracts/curation/GraphCurationToken.sol`
- [ ] **Step 5: Run** the package tests, `pnpm --filter @graphprotocol/contracts-tests test:self`, `pnpm check:bytecode` and `pnpm lint:sol && git status --short`. Expected: all pass, and no files changed.
- [ ] **Step 6:** Write `t3a.md` and run the mapping checks. Expected: 43 cases, 43 rows, no `MISSING`.
- [ ] **Step 7: Commit and open the PR.**

  ```bash
  git commit -m "test(subgraph-discovery): port L2Curation tests to Foundry"
  ```

---

### Task 3b (PR T3b): L2GNS tests

**Cases:** 35 live (`l2/l2GNS.test.ts`), plus 88 dropped (`gns.test.ts`, in one row).

**Files:**

- Create, under `packages/subgraph-discovery/test/unit/`:
  - `shared/GNSHelpers.t.sol`
  - under `l2-gns/`:
    - `PublishNewVersion.t.sol`
    - `ReceiveSubgraphFromL1.t.sol` (also holds the `onTokenTransfer with invalid codes` case)
    - `FinishSubgraphTransfer.t.sol`
    - `ReceiveCuratorBalance.t.sol`
    - `AliasedSubgraphId.t.sol`
- Create: `scripts/contracts-migration/test-mapping/t3b.md`
- Delete, under `packages/contracts-test/tests/unit/`:
  - `l2/l2GNS.test.ts`
  - `lib/gnsUtils.ts`
  - `gns.test.ts` (L1GNS, already `describe.skip`; spec §4)

**Interfaces:**

- Consumes: T3a's `DiscoveryTest`, `L2GatewayMock` and interfaces.
- Produces: nothing for other tasks.
- `abstract contract GNSHelpers is DiscoveryTest`. It ports the `lib/gnsUtils.ts` helpers that `l2GNS.test.ts` uses, assertions included:
  - `_publishNewSubgraph(address account, bytes32 deploymentId) returns (uint256 subgraphId)`. The id is `uint256(keccak256(abi.encodePacked(account, gns.nextAccountSeqID(account), block.chainid)))`.
  - `_publishNewVersion(address account, uint256 subgraphId, bytes32 newDeploymentId)`
  - `_mintSignal(address account, uint256 subgraphId, uint256 tokensIn)`
  - `_burnSignal(address account, uint256 subgraphId)`
  - `_deprecateSubgraph(address account, uint256 subgraphId)`
  - Helpers act as `account` with `vm.startPrank` / `vm.stopPrank`.
- Callhook data: `abi.encode(uint8 code, uint256 l1SubgraphID, address beneficiary)`, with code `0` for a subgraph and `1` for a curator balance. L1 deliveries go through `gatewayMock.deliver(address(gns), l1GNS, amount, data)`.

Steps:

- [ ] **Step 1: Write `GNSHelpers`** and `test_Setup_PublishNewSubgraph`. Run `pnpm --filter @graphprotocol/subgraph-discovery test`. Expected: pass.
- [ ] **Step 2: Port** `l2GNS.test.ts`, one `describe` block per file, as listed above.
  - **Front-running test:** the slippage case keeps its curation inflation (mint to curation, then `collect` as `subgraphService`). It drops the staking lines, which never affected the assertions.
  - **`DepositFinalized`:** the old assertions on `emit(l2GraphTokenGateway, 'DepositFinalized')` map to `covered by t2b L2GraphTokenGatewayTransfers`. The mock gateway doesn't emit it.
  - **`getAliasedL2SubgraphID`:** keeps the exact L1 id `68799548758199140224151701590582019137924969401915573086349306511960790045480` and the wrap-around case.
- [ ] **Step 3: Cover the checklist** for:
  - `contracts/l2/discovery/L2GNS.sol`
  - `contracts/discovery/GNS.sol`
  - `contracts/discovery/SubgraphNFT.sol`
  - `contracts/base/Multicall.sol`
  - `contracts/utils/TokenUtils.sol`, reached through GNS and L2Curation

  GNS functions that only L1GNS reached go in `## Coverage` with a reason. Add `test_GNS_Multicall` if `multicall` is listed.

- [ ] **Step 4: Run** the package tests, `pnpm --filter @graphprotocol/contracts-tests test:self`, `pnpm check:bytecode` and `pnpm lint:sol && git status --short`. Expected: all pass, and no files changed.
- [ ] **Step 5:** Write `t3b.md` and run the mapping checks. Expected: 123 cases, 36 rows (35 plus the `gns.test.ts` row), no `MISSING`.
- [ ] **Step 6: Commit and open the PR.**

  ```bash
  git commit -m "test(subgraph-discovery): port L2GNS tests to Foundry"
  ```

---

### Task 4 (PR T4): EpochManager tests in horizon

**Cases:** 11 (`epochs.test.ts`).

**Files:**

- Modify: `packages/horizon/foundry.toml` (add the artifact read permission to `fs_permissions`)
- Create, under `packages/horizon/test/unit/`:
  - `shared/ProtocolFixture.t.sol`
  - `epochs/IEpochManagerLike.sol`
  - `epochs/EpochManager.t.sol`
- Create: `scripts/contracts-migration/test-mapping/t4.md`
- Delete: `packages/contracts-test/tests/unit/epochs.test.ts`

**Interfaces:**

- Consumes: `ProtocolFixture`.
- horizon already depends on `@graphprotocol/contracts`.
- EpochManager: `PKG_ARTIFACTS + "epochs/EpochManager.sol/EpochManager.json"`, behind a proxy, `initialize(controller, 60)`. 60 is the old fixture's `lengthInBlocks`.
- `IEpochManagerLike is IEpochManager`, adding:
  - `initialize(address,uint256)`;
  - `epochLength()`, `lastRunEpoch()`, `lastLengthUpdateEpoch()`, `lastLengthUpdateBlock()`;
  - `event EpochRun(uint256 indexed epoch, address caller)`;
  - `event EpochLengthUpdate(uint256 indexed epoch, uint256 epochLength)`.

Steps:

- [ ] **Step 1: Write `EpochManager.t.sol`.** Include every `epochs.test.ts` case, plus Review Focus 4: `test_EpochManager_SameBlockDoesNotAdvance` (no roll means the same `currentEpoch` and `currentEpochBlock`).
  - The lifecycle block uses `setEpochLength(3)`.
  - Block positions use `vm.roll` relative to `currentEpochBlock()`.
- [ ] **Step 2: Run** `cd packages/horizon && forge test --match-path 'test/unit/epochs/*'`. Expected: pass. Then run `pnpm --filter @graphprotocol/horizon test`. Expected: the full horizon suite still passes.
- [ ] **Step 3: Cover the checklist** for `contracts/epochs/EpochManager.sol`. The baseline lacks `runEpoch` and `isCurrentEpochRun`, because the old test used uninstrumented sdk artifacts. The ported cases cover them anyway. Expected additions:
  - `setEpochLength` with the same value reverts `Epoch length must be different to current`;
  - `blockHash` reverts `Can only retrieve past block hashes` and `Can only retrieve hashes for last 256 blocks`;
  - `epochsSince`, `epochsSinceUpdate` and `currentEpochBlockSinceStart` return the expected values after the rolls.
- [ ] **Step 4: Run** `pnpm --filter @graphprotocol/contracts-tests test:self`, `pnpm check:bytecode` and `pnpm lint:sol && git status --short`. Then write `t4.md` and run the mapping checks. Expected: all pass, and 11 cases, 11 rows, no `MISSING`.
- [ ] **Step 5: Commit and open the PR.**

  ```bash
  git commit -m "test(horizon): port EpochManager tests to Foundry"
  ```

---

### Task 5a (PR T5a): RewardsManager fixture, mocks, interface and config tests in issuance

**Cases:** 35 (`rewards-interface` 14, `rewards-config` 21).

**Files:**

- Modify:
  - `packages/issuance/package.json`:
    - add the devDependency `"@graphprotocol/contracts": "workspace:^"` (no cycle: contracts depends only on interfaces);
    - change `"test"` to `"pnpm build && pnpm test:self"`. Spec §4: `test` builds first, so the RewardsManager artifact exists.
  - `packages/issuance/foundry.toml` (add the artifact read permission)
  - `packages/issuance/test/unit/mocks/MockGraphToken.sol` (add `function burn(uint256 amount) external`, burning from `msg.sender`)
- Create, under `packages/issuance/test/unit/`:
  - `shared/ProtocolFixture.t.sol`
  - under `rewards-manager/`:
    - `shared.t.sol` (`RewardsManagerSharedTest`)
    - `IRewardsManagerLike.sol`
    - `mocks/RMCurationMock.sol`
    - `mocks/RMIssuerMock.sol`
    - `mocks/RMIssuanceAllocatorMock.sol`
    - `mocks/RMEligibilityOracleMock.sol`
    - `interface.t.sol`
    - `config.t.sol`
- Create: `scripts/contracts-migration/test-mapping/t5a.md`
- Delete, under `packages/contracts-test/tests/unit/rewards/`:
  - `rewards-interface.test.ts`
  - `rewards-config.test.ts`

**Interfaces:**

- Consumes: `ProtocolFixture`, and issuance's `contracts/test/allocate/MockERC165.sol` and `test/unit/mocks/MockGraphToken.sol`.
- Mock names carry an `RM` prefix, because issuance already has `MockIssuanceAllocator`, `MockSubgraphService` and `RewardsEligibilityOracleMock`.
- Produces, used by T5b–T5f:
  - `RewardsManagerSharedTest`:
    - fields: `rm` (`IRewardsManagerLike`), `token` (`MockGraphToken`), `curation` (`RMCurationMock`), `issuer` (`RMIssuerMock`), `allocator` (`RMIssuanceAllocatorMock`), `oracle` (`RMEligibilityOracleMock`), and `indexer` (`makeAddr`);
    - constants: `ISSUANCE_PER_BLOCK = 200 ether`, `SIGNAL = 1500 ether`, `ALLOCATION = 12_500 ether`.
  - Helpers on `RewardsManagerSharedTest`:
    - `_signal(bytes32 sd, uint256 tokens)` calls `curation.signal`.
    - `_allocate(address allocationId, bytes32 sd, uint256 tokens)` calls `issuer.allocate(allocationId, indexer, sd, tokens)`.
    - `_close(address allocationId) returns (uint256)` calls `issuer.close`.
    - `_expectedRewardsPerSignal(uint256 blocks, uint256 totalSignal) returns (uint256)` is `blocks * ISSUANCE_PER_BLOCK * 1e18 / totalSignal`.
  - `IRewardsManagerLike is IRewardsManager, IRewardsManagerDeprecated, IManaged, IIssuanceTarget, IProviderEligibilityManagement, IERC165`. Leave out any base that `IRewardsManager` already inherits.
    - All bases come from `@graphprotocol/interfaces`, except `IERC165`, which comes from OZ5 `utils/introspection/IERC165.sol`.
    - It adds:
      - `initialize(address)`;
      - `accRewardsPerSignal()`, `accRewardsPerSignalLastBlockUpdated()`;
      - `subgraphAvailabilityOracle()`, `subgraphs(bytes32)`, `denylist(bytes32)`, `minimumSubgraphSignal()`;
      - `event ParameterUpdated(string param)`.
    - Interface-id tests use `type(IRewardsManager).interfaceId` etc., never the `Like` type.
  - `RMCurationMock(MockGraphToken token)`:
    - `setRewardsManager(address)`;
    - `signal(bytes32 sd, uint256 tokens)`: calls `rm.onSubgraphSignalUpdate(sd)`, then bumps pool tokens and mints `tokens` to itself;
    - `unsignal(bytes32 sd, uint256 tokens)`: hook first, then lowers pool tokens and burns `tokens` from itself;
    - `addFees(bytes32 sd, uint256 tokens)`: no hook; bumps pool tokens and mints;
    - `getCurationPoolTokens(bytes32) view returns (uint256)`.
  - `RMIssuerMock is IRewardsIssuer`:
    - `setRewardsManager(address)`;
    - `allocate(address allocationId, address indexer, bytes32 sd, uint256 tokens)`: `snapshot = rm.onSubgraphAllocationUpdate(sd)`, stores an active allocation `(indexer, sd, tokens, snapshot, pending 0)`, then bumps allocated tokens.
    - `close(address allocationId) returns (uint256)`: `rm.takeRewards(allocationId)` while still active, then deactivates and lowers allocated tokens. Doc comment: legacy Staking called `onSubgraphAllocationUpdate` instead for a zero POI or an allocation under one epoch old. The ported tests never hit that case.
    - `setAllocation(address allocationId, bool isActive, address indexer, bytes32 sd, uint256 tokens, uint256 accRewardsPerAllocatedToken, uint256 accRewardsPending)`;
    - `setSubgraphAllocatedTokens(bytes32, uint256)`;
    - `reclaim(bytes32 reason, address allocationId) returns (uint256)`: calls `rm.reclaimRewards`;
    - `getAllocationData` and `getSubgraphAllocatedTokens`, per `IRewardsIssuer`.
  - `RMIssuanceAllocatorMock` and `RMEligibilityOracleMock`: 0.8 ports of `packages/contracts/contracts/tests/` `MockIssuanceAllocator.sol` and `MockRewardsEligibilityOracle.sol`, with the same functions and ERC-165 answers.

**`setUp`:**

1. `vm.warp(1_700_000_000)`, `vm.roll(1_000_000)`, `_deployProtocolBase()`.
2. RewardsManager from `PKG_ARTIFACTS + "rewards/RewardsManager.sol/RewardsManager.json"` behind a proxy: `initialize(controller)`.
3. Register `GraphToken` (the MockGraphToken) and `Curation` (RMCurationMock), then call `rm.syncAllContracts()`.
4. `curation.setRewardsManager(rm)`, `issuer.setRewardsManager(rm)`.
5. As governor: `setSubgraphService(issuer)`, `setIssuancePerBlock(ISSUANCE_PER_BLOCK)`.

No artifact from horizon, subgraph-discovery or graph-token is loaded (spec §2 acyclicity).

Steps:

- [ ] **Step 1: Scaffold.** Write the mocks, `IRewardsManagerLike` and `RewardsManagerSharedTest`, plus `test_Setup_RewardsManagerWired`: `subgraphService() == issuer` and `issuancePerBlock() == 200 ether`.
- [ ] **Step 2: Run** `pnpm --filter @graphprotocol/issuance test`. Expected: the new test and the existing issuance suite pass.
- [ ] **Step 3: Port** `rewards-interface.test.ts` into `interface.t.sol`. Keep the exact interface ids: IERC165 `0x01ffc9a7`, IIssuanceTarget `0x19f6601a`, IRewardsManager `0x8469b577`.
- [ ] **Step 4: Port** `rewards-config.test.ts` into `config.t.sol`. The "initialize on implementation" case calls `initialize` on the proxy, as the old test did, and expects `Only implementation`.
- [ ] **Step 5: Run** the package tests, `pnpm --filter @graphprotocol/contracts-tests test:self`, `pnpm check:bytecode` and `pnpm lint:sol && git status --short`. Then write `t5a.md` and run the mapping checks. Expected: all pass, and 35 cases, 35 rows.
- [ ] **Step 6: Commit and open the PR.**

  ```bash
  git commit -m "test(issuance): add RewardsManager Foundry fixture and port interface and config tests"
  ```

---

### Tasks 5b–5f (PRs T5b–T5f): remaining RewardsManager tests

Each PR:

- adds `.t.sol` files under `packages/issuance/test/unit/rewards-manager/`;
- writes its own mapping file (`t5b.md` … `t5f.md`);
- deletes its TS files.

Use T5a's `RewardsManagerSharedTest`. Add a helper there only when two files need it. If two parallel PRs add the same helper, the second to rebase keeps one.

| PR  | Cases | New files                                                                           | Deleted TS files (`packages/contracts-test/tests/unit/rewards/`)                 |
| --- | ----- | ----------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| T5b | 25    | `calculations.t.sol`, `distribution.t.sol`                                          | `rewards-calculations.test.ts`, `rewards-distribution.test.ts`                   |
| T5c | 32    | `issuanceAllocator.t.sol`, `subgraphService.t.sol`                                  | `rewards-issuance-allocator.test.ts`, `rewards-subgraph-service.test.ts`         |
| T5d | 56    | `eligibility.t.sol`, `reclaim.t.sol` (split further by describe if over ~800 lines) | `rewards-eligibility-oracle.test.ts`, `rewards-reclaim.test.ts`                  |
| T5e | 21    | `signalAllocationUpdate.t.sol`, `snapshotInversion.t.sol`                           | `rewards-signal-allocation-update.test.ts`, `rewards-snapshot-inversion.test.ts` |
| T5f | 42    | `legacySuite.t.sol` (unique cases only)                                             | `rewards.test.ts`                                                                |

Decisions each port must follow:

- **Translations:**
  - `staking.allocateFrom` becomes `_allocate`, and `closeAllocation` becomes `_close`.
  - `curation.mint` becomes `_signal`.
  - `helpers.mineEpoch` and `mine(n)` become `vm.roll`.
  - The old suite set the legacy Staking contract as the subgraph service. `issuer` plays that role.
  - `staking.collect` query fees become `curation.addFees` with the curation share only. The old test set `setCurationPercentage(100000)`, so collecting 10,000 GRT is `addFees(sd, 1_000 ether)`.
- **Legacy-Staking cases** (`should distribute rewards on closed allocation and stake`, `…and send to destination`, `…w/delegators`, in T5b's distribution file and again in T5f):
  - Port the RewardsManager half: the `HorizonRewardsAssigned` amount, the mint to the issuer and the total supply.
  - Drop the stake, destination and delegation-pool assertions as `dropped: legacy Staking behaviour; Horizon equivalent in subgraph-service test/unit/subgraphService/collect/indexing/indexing.t.sol`.
  - Name the matching test functions there, such as `test_SubgraphService_Collect_Indexing_WithDelegation`.
- **`two allocations in the same block with a GRT burn in the middle`:** use `MockGraphToken.burn`.
- **T5b** also adds Review Focus 4: `test_Rewards_ZeroWhenNoBlocksElapsed`.
- **Snapshot inversion (T5e):** `vm.store` replaces `hardhat_setStorageAt`.
  - The `subgraphs` mapping is at slot 16, with fields at `+0..+3` (`accRewardsForSubgraph`, `accRewardsForSubgraphSnapshot`, `accRewardsPerSignalSnapshot`, `accRewardsPerAllocatedToken`) from `keccak256(abi.encode(sd, uint256(16)))`.
  - `test_SnapshotInversion_StorageSlotsMatchLayout` checks this before the other tests rely on it.
- **Same-block cases (T5e):** batched Hardhat automine cases become consecutive calls with no `vm.roll` in between.
- **`rewards.test.ts` (T5f).** Most of its cases duplicate files T5a–T5e already ported.
  - For each case, find the same-titled test and diff the assertions, not just the titles.
  - If the assertions match, the row points at the existing test. If they differ, port the difference into `legacySuite.t.sol`.
  - Known unique cases:
    - the 75/25 split variant of `accrued for each subgraph` (±1%);
    - `should handle zero rewards with denylist and reclaim address`;
    - `should handle zero rewards with eligibility oracle and reclaim address`;
    - `should allow collecting pre-denial rewards after undeny`;
    - `allocation created while denied should only earn post-undeny rewards`;
    - `should reclaim denied-period rewards via onSubgraphAllocationUpdate`.
- **Coverage checklist.**
  - Each of T5b–T5e runs it for `contracts/rewards/RewardsManager.sol` and records its `MISSING` names.
  - T5f closes it: every listed RewardsManager function is reached, or listed with a reason.
  - For `contracts/staking/libs/MathUtils.sol`, only `diffOrZero` is reachable from RewardsManager. `min` and `weightedAverageRoundingUp` are listed as `reached only through legacy Staking`.

Steps (each of T5b–T5f):

- [ ] **Step 1: Port** the first file listed for the PR. Run `cd packages/issuance && forge test --match-path 'test/unit/rewards-manager/<file>'`. Expected: pass.
- [ ] **Step 2: Port** the second file, if the PR has one. Run the same command for it. Expected: pass.
- [ ] **Step 3: Run** `pnpm --filter @graphprotocol/issuance test`, `pnpm --filter @graphprotocol/contracts-tests test:self`, `pnpm check:bytecode` and `pnpm lint:sol && git status --short`. Expected: all pass, and no files changed.
- [ ] **Step 4:** Write the mapping file and run the mapping checks. Expected: rows equal the PR's case count in the table, and no `MISSING`.
- [ ] **Step 5: Commit and open the PR.**

  ```bash
  git commit -m "test(issuance): port RewardsManager <area> tests to Foundry"
  ```

---

## After Phase T

- `contracts-test` contains only tests for deleted or legacy contracts, plus `subgraphAvailability.test.ts`. D1 deletes them.
- The temporary `@graphprotocol/contracts` devDependencies are removed one by one by the Phase 1 moves.
- The spec (`design.md`) was amended to match this plan: ManagedMock and TokenUtilsMock in the mocks table, ArbSysMock still deleted, no Hardhat config before Phase 1, and no allocation-flow cases moved to `packages/testing`.
