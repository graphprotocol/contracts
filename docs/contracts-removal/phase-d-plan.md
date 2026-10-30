# Contracts Removal — Phase D (Dead Code Removal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the old test suite and every dead contract from `packages/contracts`, after archiving the source that actually runs on mainnet in a new private `legacy` package.

**Architecture:**

- D1 removes `contracts-test` and `@graphprotocol/sdk`.
- D2a creates `legacy` as per-contract bundles of Sourcify-verified source, each compiled with its exact compiler and compared with committed hashes of the on-chain code. D2b adds its address book and audits.
- D3a points the Ignition modules at an npm alias of `@graphprotocol/contracts@7.3.0`, so they survive the deletions. D3b deletes the dead contracts.

**Tech Stack:** pnpm workspaces, Node 24 (`node:test`, `node:crypto`), solc-js 0.7.4 and 0.7.6 from npm, Hardhat 2, Foundry 1.8.3.

**Spec:** `docs/contracts-removal/design.md` (§2 "legacy package", §5 "Ignition", §5 "address-book", "PR sequence → Phase D").

## Global Constraints

- Each task is a draft PR in one chain, the same way as Phase T: D1 targets `chore/contracts-removal-phase-0` (#1373), D2a targets D1's branch, then D2b, D3a and D3b each target the one before. Nothing goes to main before the audit.
- Conventional commits, no Co-Authored-By line and no Claude attribution in commits or PRs.
- Sources under `packages/legacy/verified/` are never edited, formatted or linted.
- No RPC URL or API key is ever written to a file, commit, report or PR. RPC URLs are passed only as inline env vars.
- D3b's list comes from the spec. Do not delete any other contract.
- `packages/legacy` never gets a `.solhint.json`: CI's changed-files mode runs solhint from that package and passes only because it loads no rules there.
- D1 starts after #1387 merges into the base branch, so the stack starts from the integration tip.
- Ignition module changes are limited to the package name in import lines. Journals under `ignition/deployments/` don't change.

**Verification for every PR**, run from the repo root after committing. It runs what CI runs, except coverage:

```bash
pnpm install --frozen-lockfile
pnpm -r --sequential run build
pnpm test:scripts
pnpm check:bytecode
pnpm -r --sequential run test:self
pnpm lint:sol && git status --short
```

Expected: all exit 0, and `git status` prints nothing.

## Review Focus

1. **A formatter or linter rewrites a verified source.** `lint:sol`, the lint-staged commit hook and CI's Solidity lint must all leave `verified/` alone. Compiling can't detect this, because formatting doesn't change bytecode, so D2a compares source hashes after the commit.
2. **A changed verified source goes unnoticed.** Verification must fail, whether or not the code changes. D2a has a test for each case.
3. **An implementation on mainnet has been replaced since the addresses were listed.** `record-mainnet` must fail rather than hash a stale one. It reads each proxy's slot, and for StakingExtension, which has no proxy, L1Staking's `extensionImpl`.
4. **The alias changes what Solidity compiles.** Foundry's remapping auto-detection or Hardhat could pick up the alias's sources. D3a pins this with `check:bytecode` and the horizon and subgraph-service suites.
5. **Modules fail only when loaded.** Hardhat loads `tasks/deploy.ts` only in a built project, so a broken import can pass `build`. D3a and D3b run `npx hardhat --help` in both packages after the build.

---

### Task D1: Delete `contracts-test` and the sdk

**Files:**

- Delete: `packages/contracts-test/` (with `rm -rf`, because `git rm` leaves `node_modules`, `artifacts` and `types`)
- Delete: `packages/contracts/.mocharc.json`
- Delete: `packages/contracts/scripts/ops/20240208-migrate-legacy-subgraphs/`, `packages/contracts/scripts/ops/testDisputeConflict/` (their only sdk users outside `contracts-test`; the package doesn't depend on the sdk, so they can't run today)
- Modify: `packages/contracts/package.json` (remove the `test` and `test:coverage` scripts, and `test/node_modules/` from `clean`)
- Modify: `packages/contracts/tsconfig.json` (remove the `test/**/*.ts` include), `packages/contracts/hardhat.config.ts` (remove `paths.tests`)
- Modify: `pnpm-workspace.yaml` (remove `'@graphprotocol/sdk'` from the catalog, and the whole `minumumReleaseAgeExclude` key, whose only entry it is)
- Modify: `.gitignore` (remove `packages/contracts-test/types/`)
- Modify: `pnpm-lock.yaml`

**Interfaces:**

- Consumes: nothing.
- Produces: no package runs `contracts-test`. `scripts/contracts-migration/coverage-baseline.json` and `summarize-coverage.mjs` stay, for the Phase 1 coverage gate.

`packages/contracts/test/` no longer exists, and `build-test.yml` finds coverage files with `find`, so neither needs a change. Say so in the PR.

- [ ] **Step 1: Confirm the deleted suite covers only dead code.** Run `pnpm --filter @graphprotocol/contracts-tests test:self`. Expected: `361 passing`, 0 failing. Run `git ls-files packages/contracts-test/tests`. Expected: only `curation/`, `disputes/`, `l2/l2Staking.test.ts`, `lib/`, `payments/`, `rewards/subgraphAvailability.test.ts`, `serviceRegisty.test.ts` and `staking/`.
- [ ] **Step 2: Make the deletions and edits above.**
- [ ] **Step 3: Update the lockfile.** Run `pnpm install --no-frozen-lockfile`. Expected: `@graphprotocol/sdk` no longer appears in `pnpm-lock.yaml`.
- [ ] **Step 4: Check no reference is left.** Run `git grep -nE "contracts-tests?\b|@graphprotocol/sdk" -- ':!docs/contracts-removal' ':!**/CHANGELOG.md' ':!scripts/contracts-migration'`. Expected: no output.
- [ ] **Step 5: Commit.** `chore: remove contracts-test and the sdk`
- [ ] **Step 6: Run the verification block.** Expected: `test:self` no longer runs `contracts-tests`, and `check:bytecode` prints `OK: 26 contracts match`.

---

### Task D2a: Create `legacy` with verified bundles

**Files:**

- Create: `packages/legacy/package.json`, `packages/legacy/README.md`
- Create: `packages/legacy/scripts/lib.mjs`, `scripts/fetch-verified.mjs`, `scripts/record-mainnet.mjs`, `scripts/verify.mjs`, `scripts/lib.test.mjs`
- Create: `packages/legacy/targets.json`, `packages/legacy/mainnet.json`
- Create: `packages/legacy/verified/<Contract>/compiler.json`, `verified/<Contract>/sources/**`
- Modify: `.prettierignore`, `.solhintignore` (create it), both adding `packages/legacy/verified/`
- Modify: `scripts/lint-staged-run.sh` (add `"/packages/legacy/verified/"` to `IGNORE_SUBSTRINGS`), `package.json` (wrap both `*.sol` lint-staged commands in `scripts/lint-staged-run.sh`). Without this the commit hook fails: `solhint` exits 255 when every staged file is ignored
- Modify: `pnpm-lock.yaml`

**Interfaces:**

- Consumes: nothing.
- Produces: `pnpm --filter @graphprotocol/legacy test:self`, which later tasks rely on to prove the archive still reproduces mainnet.

`package.json`: name `@graphprotocol/legacy`, `"private": true`, version `0.0.0`, license `GPL-2.0-or-later`, devDependencies exactly `"solc-0.7.4": "npm:solc@0.7.4"` and `"solc-0.7.6": "npm:solc@0.7.6"`, script `"test:self": "node --test 'scripts/*.test.mjs' && node scripts/verify.mjs"`. No `build` script. CI's `pnpm -r run test:self` is its CI job, so no workflow changes.

`targets.json`, the implementations to archive:

| Contract            | Implementation                               | Proxy                                        | solc  |
| ------------------- | -------------------------------------------- | -------------------------------------------- | ----- |
| GraphToken          | `0xc944E90C64B2c07662A292be6244BDf05Cda44a7` | none                                         | 0.7.4 |
| L1GraphTokenGateway | `0xD41ca6A1d034D178c196DFa916f22f7D1a1B8222` | `0x01cDC91B0A9bA741903aA3699BF4CE31d6C5cC06` | 0.7.6 |
| BridgeEscrow        | `0xBcD54513aa593646d72aEA31406c633C235Ad6EA` | `0x36aFF7001294daE4C2ED4fDEfC478a00De77F090` | 0.7.6 |
| L1GNS               | `0x83A5B6C542aB20436087Fc79724bdF06ea80f836` | `0xaDcA0dd4729c8BA3aCf3E99F3A9f471EF37b6825` | 0.7.6 |
| Curation            | `0xDeb46851907fd85DD475780CcE2eE0D67c969825` | `0x8FE00a685Bcb3B2cc296ff6FfEaB10acA4CE1538` | 0.7.6 |
| L1Staking           | `0x20a14D78848BC8B3F3d4B77239F2adC3C0259A10` | `0xF55041E37E12cD407ad00CE2910B8269B01263b9` | 0.7.6 |
| StakingExtension    | `0xA479c00cDa8C07bce458D7a826C7b091672EB92C` | none                                         | 0.7.6 |

Functions in `scripts/lib.mjs`:

- `normalizeRuntime(hex: string, ranges: {start: number, length: number}[]): string`: lowercases, drops `0x`, zeroes each byte range, and removes the trailing CBOR metadata using the length in the last 2 bytes.
- `runtimeRanges(deployedBytecode): {start, length}[]`: every entry of `immutableReferences` and `linkReferences`.
- `compileBundle(dir: string): {object: string, ranges: {start, length}[]}`: builds a solc standard-JSON input from `compiler.json` and the files under `sources/`, with each path relative to `sources/` as the source key and `settings.outputSelection` set to `evm.deployedBytecode.{object,immutableReferences,linkReferences}`. It sets `language: 'Solidity'`, loads `solc-0.7.4` or `solc-0.7.6` (the version without `+commit...`) through `createRequire`, asserts `solc.version()` starts with the full version string, throws on any error-severity output, and returns the target's output.
- `runtimeHash(normalized: string): string`: sha256 hex.

- `checkSources(dir: string): string[]`: compares the files under `sources/` with `sourceHashes` in `compiler.json` and returns each path that is missing, extra or changed.

`compiler.json` keeps `version` (the full `0.7.6+commit.7338295f` string), `settings` (everything from Sourcify except `outputSelection`, including `evmVersion` and `libraries`), `target` (`{source, name}`, split from `fullyQualifiedName`), `sourcifyMatch` and `sourceHashes` (path to sha256).

- [ ] **Step 1: Write the failing tests** in `scripts/lib.test.mjs`:

```js
test('normalizeRuntime zeroes ranges and removes metadata', () => {
  // 4 code bytes, then a 2-byte CBOR blob and its 2-byte length
  assert.equal(normalizeRuntime('0xAABBCCDD' + 'eeff' + '0002', [{ start: 1, length: 2 }]), 'aa0000dd')
})

test('runtimeRanges reads immutable and link references', () => {
  const ranges = runtimeRanges({
    immutableReferences: { 1: [{ start: 3, length: 32 }] },
    linkReferences: { 'a.sol': { Lib: [{ start: 40, length: 20 }] } },
  })
  assert.deepEqual(ranges, [
    { start: 3, length: 32 },
    { start: 40, length: 20 },
  ])
})

test('verified BridgeEscrow matches mainnet.json', () => {
  const { object, ranges } = compileBundle(BRIDGE_ESCROW_DIR)
  assert.equal(runtimeHash(normalizeRuntime(object, ranges)), mainnet.BridgeEscrow.runtimeHash)
})

test('a code change no longer matches mainnet.json', () => {
  // Copy the bundle to a temp dir and insert a function right after the target contract's opening brace
  const { object, ranges } = compileBundle(copyOfBridgeEscrowWithFunctionInserted())
  assert.notEqual(runtimeHash(normalizeRuntime(object, ranges)), mainnet.BridgeEscrow.runtimeHash)
})

test('a comment-only change fails the source check', () => {
  // Bytecode doesn't change here, so only the hashes can catch it
  assert.deepEqual(checkSources(copyOfBridgeEscrowWithCommentAdded()), [TARGET_SOURCE_PATH])
})
```

- [ ] **Step 2: Run them.** `cd packages/legacy && node --test scripts/lib.test.mjs`. Expected: FAIL, with `lib.mjs` not implemented.
- [ ] **Step 3: Implement `scripts/lib.mjs`.** The first two tests pass.
- [ ] **Step 4: Implement and run `scripts/fetch-verified.mjs`.** For each target, it reads `https://sourcify.dev/server/v2/contract/1/<implementation>?fields=stdJsonInput,compilation` and writes `compiler.json`, including `sourceHashes`, and each source's `content` byte for byte. Expected: 7 folders. `verified/GraphToken/sources/` has 1 file, and the file counts of the others are, in the table's order, 26, 18, 38, 33, 35 and 23.
- [ ] **Step 5: Implement and run `scripts/record-mainnet.mjs`.** It requires `MAINNET_RPC_URL` and exits 1 without it. For each target with a proxy, it reads the EIP-1967 slot `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc` and exits 1 if it isn't the target's implementation (Review Focus 3). For StakingExtension, it reads `extensionImpl` on the L1Staking proxy, with the slot taken from L1Staking's compiler `storageLayout`, and exits 1 if it isn't the target. It then calls `eth_getCode`, normalizes with the ranges from `compileBundle`, and writes `mainnet.json` as `{ <Contract>: { implementation, proxy, runtimeHash } }`. Run `MAINNET_RPC_URL=<url> node scripts/record-mainnet.mjs`. Any public mainnet RPC works, because the data is public.
- [ ] **Step 6: Implement `scripts/verify.mjs`.** For each folder under `verified/` it runs `checkSources`, then compiles, normalizes and compares with `mainnet.json`. It prints each mismatch and exits 1 on any, and fails if `verified/` and `mainnet.json` don't list the same contracts. On success it prints `OK: 7 mainnet implementations reproduce`.
- [ ] **Step 7: Run it.** `pnpm --filter @graphprotocol/legacy test:self`. Expected: all tests pass and the `OK` line prints.
- [ ] **Step 8: Add the ignore entries,** and write `README.md`: what the archive is, the table above, that current source reproduces only Curation, that GraphToken and L1Staking are Sourcify partial matches so their sources may differ from the deployed ones outside the code, how to re-run the fetch and record scripts, and that the sources must stay unformatted.
- [ ] **Step 9: Commit,** with the hook enabled so lint-staged runs (never `--no-verify`). `feat(legacy): archive verified mainnet implementations`
- [ ] **Step 10: Prove the hook and linters left the sources alone.** Run `pnpm --filter @graphprotocol/legacy test:self`, then the verification block. Expected: the `OK` line prints, so every source hash still matches, and `git status` stays empty. If the hook reformatted a source, fix the ignore file and re-fetch before amending.

---

### Task D2b: Add the legacy address book and audits

**Files:**

- Create: `packages/legacy/addresses.json`
- Create: `packages/address-book/src/legacy/addresses.json`
- Move: `packages/contracts/audits/` to `packages/legacy/audits/` (`git mv`)
- Modify: `packages/address-book/scripts/sources.js` (add `'legacy'`, and correct its comment), `packages/address-book/README.md` (the sources are regular files, not symlinks)
- Create: a changeset for `@graphprotocol/address-book`, which gains a published export
- Modify: `packages/legacy/README.md`

**Interfaces:**

- Consumes: the `legacy` package from D2a.
- Produces: `@graphprotocol/address-book` exposes `src/legacy/addresses.json`.

`legacy/addresses.json` holds the `1` and `11155111` entries of `packages/contracts/addresses.json`, unchanged and complete, including Controller, EpochManager, RewardsManager, DisputeManager, ServiceRegistry, GraphProxyAdmin and SubgraphNFT. Copy `packages/legacy/addresses.json` to `packages/address-book/src/legacy/addresses.json` as a regular file, like the other four (mode 100644, byte-identical to their sources). Don't run `restore-symlinks`.

Adding GraphCurationToken and SubgraphNFTDescriptor to `horizon/addresses.json` is Phase 1 step 3, not this task.

- [ ] **Step 1: Generate `addresses.json`** with a one-off Node command, then compare: `node -e` that deep-equals `addresses.json['1']` and `['11155111']` with `packages/contracts/addresses.json`. Expected: equal, and the top-level keys are exactly `1` and `11155111`.
- [ ] **Step 2: Make the other changes.**
- [ ] **Step 3: Check the audits moved.** Run `ls packages/legacy/audits | wc -l` and compare with the count before the move. Run `git grep -n "contracts/audits" -- ':!**/CHANGELOG.md' ':!docs/contracts-removal'`, and update any link it finds.
- [ ] **Step 4: Commit.** `feat(legacy): add address book and historical audits`
- [ ] **Step 5: Run the verification block.**

---

### Task D3a: Point Ignition at the 7.3.0 alias

**Files:**

- Modify: `packages/horizon/package.json`, `packages/subgraph-service/package.json` (add the devDependency `"@graphprotocol/contracts-7.3.0": "npm:@graphprotocol/contracts@7.3.0"`; keep the `@graphprotocol/contracts` workspace dependency)
- Modify: the 15 import-holding files under `ignition/modules/`: in horizon `core/HorizonStaking.ts`, `migrate/migrate-4.ts`, `proxy/GraphProxy.ts` and `periphery/{Controller,Curation,EpochManager,GNS,GraphProxyAdmin,GraphToken,GraphTokenGateway,RewardsManager}.ts`; in subgraph-service `Curation.ts`, `DisputeManager.ts`, `GNS.ts`, `ServiceRegistry.ts`
- Modify: `packages/horizon/scripts/pre-verify`, `packages/subgraph-service/scripts/pre-verify`, `packages/horizon/tenderly.config.json` (`../contracts/artifacts` becomes `node_modules/@graphprotocol/contracts-7.3.0/artifacts`; the tarball ships `artifacts/build-info`)
- Modify: `pnpm-lock.yaml`

**Interfaces:**

- Consumes: nothing.
- Produces: the modules and their verification tooling no longer read artifacts from the workspace package, so D3b and Phase 1 can remove them.

- [ ] **Step 1: Add the dependency,** and run `pnpm install --no-frozen-lockfile`.
- [ ] **Step 2: Replace the package name.** First run `git grep -l "@graphprotocol/contracts/artifacts" -- 'packages/*/ignition/modules/**' | wc -l`. Expected: `15`. In the listed files only, `@graphprotocol/contracts/artifacts/` becomes `@graphprotocol/contracts-7.3.0/artifacts/`.
- [ ] **Step 3: Check the diff is only that.** Run `git diff -- 'packages/*/ignition/**' | grep -E '^[-+][^-+]' | grep -v "@graphprotocol/contracts"`. Expected: no output. Run `git diff --stat -- 'packages/*/ignition/deployments/**'`. Expected: no output. Run `git grep -n "@graphprotocol/contracts/artifacts" -- 'packages/*/ignition/modules/**'`. Expected: no output.
- [ ] **Step 4: Commit.** `chore(ignition): read deployment artifacts from published contracts 7.3.0`
- [ ] **Step 5: Run the verification block.** Expected: `check:bytecode` still prints `OK: 26 contracts match`, and horizon's and subgraph-service's suites pass unchanged (Review Focus 4).
- [ ] **Step 6: Load the modules.** Run `npx hardhat --help` and `npx tsc --noEmit -p .` in `packages/horizon` and `packages/subgraph-service`. Expected: `--help` exits 0 in both, and `tsc` reports no error mentioning `contracts-7.3.0`.

---

### Task D3b: Delete the dead contracts

**Files:**

- Delete, under `packages/contracts/contracts/`:
  - `discovery/L1GNS.sol`, `discovery/L1GNSStorage.sol`, `curation/Curation.sol`, `bancor/BancorFormula.sol`
  - `staking/Staking.sol`, `staking/L1Staking.sol`, `staking/L1StakingStorage.sol`, `staking/StakingExtension.sol`, `staking/StakingStorage.sol`, `staking/libs/Stakes.sol`, `staking/libs/Exponential.sol`, `staking/libs/LibFixedMath.sol`, `l2/staking/L2Staking.sol`
  - `disputes/DisputeManager.sol`, `disputes/DisputeManagerStorage.sol`, `discovery/ServiceRegistry.sol`, `discovery/ServiceRegistryStorage.sol`
  - `payments/AllocationExchange.sol`, `discovery/erc1056/EthereumDIDRegistry.sol`, `rewards/SubgraphAvailabilityManager.sol`
  - `tests/arbitrum/ArbSysMock.sol`, `tests/ens/IENS.sol`, `tests/ens/IPublicResolver.sol`, `tests/ens/ITestRegistrar.sol`, `tests/LegacyGNSMock.sol`, `tests/MockERC165.sol`, `tests/MockSubgraphService.sol`, `tests/L1GraphTokenLockTransferToolMock.sol`, `tests/L1GraphTokenLockTransferToolBadMock.sol`
- Delete: `packages/contracts/addresses-staging.json`, `packages/contracts/arbitrum-addresses.json`, `packages/contracts/config/` (`addresses-local.json` is not tracked)
- Modify: `packages/contracts/index.js`, `packages/contracts/index.d.ts` (remove `configDir`)
- Modify: `packages/deployment/test/bytecode-comparison.test.ts:235,239` (load `('l2/curation', 'L2Curation')` and `('l2/token', 'L2GraphToken')` instead of the deleted Staking and Curation)
- Modify: `packages/contracts/hardhat.config.ts` (remove the `StakingExtension` warnings entry)
- Modify: `scripts/contracts-migration/manifest.json`, `scripts/contracts-migration/reference.json` (remove `L1GNS`, `Curation`, `L1Staking`, `StakingExtension`, `LibExponential`)

**Interfaces:**

- Consumes: `legacy` from D2a, and the Ignition alias from D3a.
- Produces: `packages/contracts` holds only live contracts and the mocks ported tests use: 45 Solidity files. Other leftovers that point at deleted things (`.env.example`, `scripts/upgrade`) stay until Phase 2a deletes the package.

Edit `reference.json` by removing those 5 keys. Don't regenerate it with `--write`: leaving the other 21 hashes untouched is what shows the deletions changed no live bytecode.

- [ ] **Step 1: Make the deletions and edits.**
- [ ] **Step 2: Rebuild from clean.** Run `pnpm --filter @graphprotocol/contracts clean && pnpm --filter @graphprotocol/contracts build`. Expected: exit 0. A stale artifact mustn't hide a broken import.
- [ ] **Step 3: Commit.** `refactor(contracts): delete dead contracts now archived in legacy`
- [ ] **Step 4: Run the verification block.** Expected: `check:bytecode` prints `OK: 21 contracts match`, and `test:self` includes `OK: 7 mainnet implementations reproduce`.
- [ ] **Step 5: Count what's left.** Run `git ls-files 'packages/contracts/contracts/*.sol' | wc -l`. Expected: `45`.
- [ ] **Step 6: Load the modules.** Run `npx hardhat --help` in `packages/horizon` and `packages/subgraph-service`. Expected: exit 0 (Review Focus 5).
- [ ] **Step 7: Check nothing else consumed them.** Run `git grep -nE "@graphprotocol/contracts/(artifacts/)?contracts/(staking/(Staking|L1Staking|StakingExtension|StakingStorage)|disputes/|payments/|curation/Curation\.|bancor/|discovery/(L1GNS|ServiceRegistry))" -- ':!**/CHANGELOG.md' ':!docs/contracts-removal'` and `git grep -nE "loadContractsArtifact\('(staking|curation|disputes|bancor|payments)'" -- packages/deployment`. Expected: no output.
