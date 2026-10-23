# Contracts Removal — Phase 0 (Preparation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the four preparation PRs that every later phase depends on:

- 0a: delete the legacy task package.
- 0b: decouple token-distribution.
- 0c: a bytecode equivalence check.
- 0d: a coverage baseline.

**Architecture:**

- 0a and 0b are pure removals and import swaps.
- 0c adds a small Node script with a committed manifest (contract → artifact path) and reference (contract → hashes of metadata-stripped bytecode). Every later move PR updates the manifest and must keep the hashes identical. CI runs it after the build.
- 0d adds an lcov summarizer and commits the per-file line coverage of `contracts-test` as the parity baseline for the Foundry ports.

**Tech Stack:** pnpm workspaces, Node 24 (`node:test`, `node:crypto`), Hardhat 2 / solidity-coverage (contracts-test), GitHub Actions.

**Spec:** `docs/contracts-removal/design.md` (sections "PR sequence → Phase 0", §5 "Removed tooling and CI", §5 "token-distribution", §4 "Coverage").

Later phases (T, D, 1, 2) get their own plans, written once Phase 0 has landed, because they depend on what 0c and 0d produce.

## Global Constraints

- **Prerequisite:** merge the `docs/contracts-package-removal-spec` branch (spec and this plan) to `main` before starting, so every task branch has both documents.
- Package manager: pnpm. Run `pnpm install` after any `package.json` change and commit `pnpm-lock.yaml`.
- One PR per task. Branch off `main`: `chore/contracts-removal-0a-delete-task`, `…-0b-token-distribution`, `…-0c-bytecode-check`, `…-0d-coverage-baseline`.
- Commits use conventional messages (`chore:`, `test:`, `feat:`, `ci:`). Do NOT add `Co-Authored-By` lines.
- No contract source changes in Phase 0.
- Bytecode comparison strips the exact CBOR metadata blob `a264697066735822<68 hex>64736f6c6343<6 hex>0033`, wherever it occurs. Any other difference, including bytes after the metadata, is a failure.
- `reference.json` hashes never change. Later PRs may change `manifest.json` paths. Entries are removed from both files only when their contract is deleted.
- Migration helper files live in `scripts/contracts-migration/`. They are deleted in Phase 2a.
- Node test runner: always pass a glob such as `node --test 'scripts/**/*.test.mjs'`. On Node 24, a directory argument is treated as a single test file and fails.

## Review Focus

1. **Missing artifact** (package not built, or a stale manifest path). `check-bytecode` must exit 1 and name the missing path on stderr. It must never skip the entry and pass. → Task 3 test `fails when an artifact is missing`.
2. **Partial reference on `--write`.** If any manifest artifact is missing, `--write` must exit 1 without touching `reference.json`. → Task 3 test `write refuses to produce a partial reference`.
3. **Metadata-only vs code differences.**
   - Artifacts that differ only in the metadata hash must pass.
   - A one-byte difference before the metadata must fail, and so must one after it (GraphProxy, PaymentsEscrow and others have real bytes after the metadata in their creation bytecode).
   - → Task 3 tests `ignores metadata-only differences`, `detects code differences` and `detects differences after the metadata`.
4. **Empty bytecode.** A manifest entry pointing at an interface or abstract contract (`bytecode` = `0x`) must fail, not hash the empty string. → Task 3 test `rejects empty bytecode`.
5. **lcov path normalization.** solidity-coverage writes absolute `SF:` paths whose ancestors can also be named `contracts`; locally and in CI the repo root itself is `contracts`. Keys must be `contracts/…` measured from the _last_ `contracts` segment. `LF:0` gets `pct: null`. → Task 4 tests.

---

### Task 1 (PR 0a): Delete `packages/contracts/task` and `verifydeployed.yml`

**Files:**

- Delete: `packages/contracts/task/` (entire directory; package `@graphprotocol/contracts-task`)
- Delete: `.github/workflows/verifydeployed.yml`
- Modify: `package.json` (root) — in `scripts.lint:yaml`, remove `packages/contracts/task/config/*.yml`
- Modify: `packages/testing/foundry.toml:35-38` — the comment's example path mentions `@graphprotocol/contracts/task/...`. Reword it to "this package's pnpm-hoisted node_modules" without that example, and keep `lint_on_build = false`.
- Modify: `pnpm-lock.yaml` (regenerated)

**Interfaces:**

- Consumes: nothing.
- Produces: no `@graphprotocol/contracts-task` package in the workspace.

- [ ] **Step 1: Confirm nothing else depends on the package**

Run: `grep -rn "contracts-task\|contracts/task" --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=artifacts --exclude-dir=cache . | grep -v '^./packages/contracts/task/' | grep -v '^./docs/contracts-removal/'`
Expected: only `package.json` (lint:yaml), `pnpm-lock.yaml` and `packages/testing/foundry.toml`.

- [ ] **Step 2: Delete the directory and workflow, then edit the root `lint:yaml` and the `testing/foundry.toml` comment as listed above**

- [ ] **Step 3: Reinstall and build**

Run: `pnpm install && pnpm build`
Expected: install succeeds with no reference to `@graphprotocol/contracts-task`, and the build succeeds.

- [ ] **Step 4: Run the affected suites**

Run: `pnpm --filter @graphprotocol/contracts-tests test:self && pnpm --filter @graphprotocol/testing test:self && pnpm lint:yaml`
Expected: all pass. contracts-tests only uses `configDir` from `@graphprotocol/contracts`, never the task package.

- [ ] **Step 5: Commit and open PR**

```bash
git add -A packages/contracts/task .github/workflows/verifydeployed.yml package.json packages/testing/foundry.toml pnpm-lock.yaml
git commit -m "chore: remove legacy contracts-task package and verifydeployed workflow"
```

PR description:

- The task package is replaced by `packages/deployment`.
- `verifydeployed.yml` is already broken: its `verify-defender` task exists only in the task package. Its network options include dead networks.

---

### Task 2 (PR 0b): Move token-distribution tests off `@graphprotocol/contracts`

**Files:**

- Modify: `packages/token-distribution/test/tokenLockWallet.test.ts:4,215,263`
- Modify: `packages/token-distribution/test/l2TokenLockManager.test.ts:4,78`
- Modify: `packages/token-distribution/test/l1TokenLockTransferTool.test.ts:4`
- Modify: `packages/token-distribution/package.json` — remove the `"@graphprotocol/contracts": "workspace:^"` devDependency
- Modify: `pnpm-lock.yaml`

**Interfaces:**

- Consumes: the IStaking ABI from `@graphprotocol/interfaces/artifacts/contracts/contracts/staking/IStaking.sol/IStaking.json`, and ethers v5's `Contract` (token-distribution's own `ethers`, 5.8.0). The tests call only `stake(uint256)` and `setController(address)` through `lockAsStaking`, plus the `.address` property.
- Do NOT use `@graphprotocol/interfaces/types-v5`. At runtime its factories `require("ethers")` from the interfaces package, which is v6, and return v6 contracts without `.address`. Under token-distribution's node10 resolution it also fails to type-check.
- Produces: token-distribution no longer depends on `@graphprotocol/contracts`.

- [ ] **Step 1: Record the current state on `main`**

Run:

```bash
cd packages/token-distribution && pnpm build && npx tsc --noEmit --incremental false > /tmp/td-tsc-before.txt
STUDIO_API_KEY=<key> pnpm test:self 2>&1 | tail -40
```

Expected: `td-tsc-before.txt` holds the existing type errors, which are pre-existing and unrelated. Record the mocha `passing` count.

- [ ] **Step 2: Swap the imports in all three files**

- Remove the `@graphprotocol/contracts/types` import.
- Add `import { Contract } from 'ethers'` (merge it into an existing `ethers` import if there is one) and `import IStakingArtifact from '@graphprotocol/interfaces/artifacts/contracts/contracts/staking/IStaking.sol/IStaking.json'`.
- Replace each `Staking__factory.connect(tokenLock.address, deployer.signer)` with `new Contract(tokenLock.address, IStakingArtifact.abi, deployer.signer)`.
- Type `lockAsStaking` as `Contract` (in `l2TokenLockManager.test.ts:78`, replace `Staking`).

If `resolveJsonModule` is not enabled in token-distribution's `tsconfig.json`, use `require(...)` the same way other JSON is loaded in that package, rather than changing the tsconfig.

- [ ] **Step 3: Remove the dependency and reinstall**

Remove the devDependency from `packages/token-distribution/package.json`, then run `pnpm install`.
Expected: the lockfile no longer links `@graphprotocol/contracts` into token-distribution.

- [ ] **Step 4: Type-check for new errors only**

Run: `cd packages/token-distribution && npx tsc --noEmit --incremental false > /tmp/td-tsc-after.txt; diff /tmp/td-tsc-before.txt /tmp/td-tsc-after.txt`
Expected: no lines that appear only in the "after" file. Hardhat's ts-node runs without type checking, so this is the only type gate.

- [ ] **Step 5: Run the tests**

Run: `cd packages/token-distribution && STUDIO_API_KEY=<key> pnpm test:self 2>&1 | tail -40`
Expected: the same `passing` count as Step 1, with 0 failing and a non-zero exit code on failure. Without `STUDIO_API_KEY` the script prints a warning and exits 0 without running anything. If no key is available locally, say so in the PR and confirm the count in CI's log, where the key is set.

- [ ] **Step 6: Commit and open PR**

```bash
git add packages/token-distribution/test packages/token-distribution/package.json pnpm-lock.yaml
git commit -m "test(token-distribution): use IStaking ABI from interfaces instead of contracts types"
```

PR description: mention that `scripts/test` skips everything and exits 0 when `STUDIO_API_KEY` is unset. That's out of scope here.

---

### Task 3 (PR 0c): Bytecode equivalence check

**Files:**

- Create: `scripts/lib/bytecode.mjs`
- Modify: `scripts/compare-repo-contract-bytecode-excluding-metadata.mjs` — delete its local `stripMetadata` and import it from `./lib/bytecode.mjs`
- Create: `scripts/contracts-migration/check-bytecode.mjs`
- Create: `scripts/contracts-migration/check-bytecode.test.mjs`
- Create: `scripts/contracts-migration/manifest.json`
- Create: `scripts/contracts-migration/reference.json` (generated)
- Modify: `package.json` (root) — add scripts `"check:bytecode": "node scripts/contracts-migration/check-bytecode.mjs"` and `"test:scripts": "node --test 'scripts/**/*.test.mjs'"`
- Modify: `.github/workflows/build-test.yml` — add a step `Check bytecode equivalence` (`pnpm check:bytecode`) right after "Build all packages", and a step `Test scripts` (`pnpm test:scripts`)

**Interfaces:**

- Produces, from `scripts/lib/bytecode.mjs`:
  - `stripMetadata(bytecode: string): string`. Lowercases the input, strips a leading `0x`, then removes every match of `/a264697066735822[0-9a-f]{68}64736f6c6343[0-9a-f]{6}0033/g`. That pattern covers the 0.7.6 suffix (`…430007060033`) and the 0.8.35 suffix (`…430008230033`). Bytes before or after a blob are kept.
  - `bytecodeHash(bytecode: string): string`. Returns the sha256 hex of `stripMetadata(bytecode)`.
- Produces, from `scripts/contracts-migration/check-bytecode.mjs`:
  - `computeHashes(manifest: Record<string,string>, repoRoot: string): { hashes: Record<string,{bytecode:string,deployedBytecode:string}>, missing: string[], empty: string[] }`.
    - Reads each artifact JSON's `bytecode` and `deployedBytecode`.
    - A missing file goes to `missing`.
    - A missing, `''` or `'0x'` `bytecode` or `deployedBytecode` goes to `empty`.
  - `compare(reference, hashes): string[]`. Returns one line per mismatch (`EpochManager: deployedBytecode differs`) and one per entry present on only one side (`X: not in reference` / `X: not in manifest`).
  - CLI, optional flags `--root <dir> --manifest <file> --reference <file>`; defaults are the repo root and the two files next to the script.
    - Without `--write`: if `missing` or `empty` is non-empty, print each entry to **stderr** and exit 1. Otherwise print the mismatches to stderr and exit 1 if there are any, else print `OK: <n> contracts match` to stdout and exit 0.
    - With `--write`: exit 1 without writing if `missing` or `empty` is non-empty. Otherwise write `reference.json` with keys sorted, 2-space indent and a trailing newline.
  - Run the CLI only when the file is executed directly: `import.meta.url === pathToFileURL(process.argv[1]).href`.
- Produces `manifest.json`: contract name → artifact path relative to the repo root.

Initial `manifest.json` (26 entries; every path was confirmed to exist after `pnpm build`):

| Name                  | Artifact path                                                                                                |
| --------------------- | ------------------------------------------------------------------------------------------------------------ |
| Controller            | `packages/contracts/artifacts/contracts/governance/Controller.sol/Controller.json`                           |
| GraphProxy            | `packages/contracts/artifacts/contracts/upgrades/GraphProxy.sol/GraphProxy.json`                             |
| GraphProxyAdmin       | `packages/contracts/artifacts/contracts/upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json`                   |
| GraphToken            | `packages/contracts/artifacts/contracts/token/GraphToken.sol/GraphToken.json`                                |
| L2GraphToken          | `packages/contracts/artifacts/contracts/l2/token/L2GraphToken.sol/L2GraphToken.json`                         |
| L1GraphTokenGateway   | `packages/contracts/artifacts/contracts/gateway/L1GraphTokenGateway.sol/L1GraphTokenGateway.json`            |
| L2GraphTokenGateway   | `packages/contracts/artifacts/contracts/l2/gateway/L2GraphTokenGateway.sol/L2GraphTokenGateway.json`         |
| BridgeEscrow          | `packages/contracts/artifacts/contracts/gateway/BridgeEscrow.sol/BridgeEscrow.json`                          |
| L2GNS                 | `packages/contracts/artifacts/contracts/l2/discovery/L2GNS.sol/L2GNS.json`                                   |
| L2Curation            | `packages/contracts/artifacts/contracts/l2/curation/L2Curation.sol/L2Curation.json`                          |
| GraphCurationToken    | `packages/contracts/artifacts/contracts/curation/GraphCurationToken.sol/GraphCurationToken.json`             |
| SubgraphNFT           | `packages/contracts/artifacts/contracts/discovery/SubgraphNFT.sol/SubgraphNFT.json`                          |
| SubgraphNFTDescriptor | `packages/contracts/artifacts/contracts/discovery/SubgraphNFTDescriptor.sol/SubgraphNFTDescriptor.json`      |
| EpochManager          | `packages/contracts/artifacts/contracts/epochs/EpochManager.sol/EpochManager.json`                           |
| RewardsManager        | `packages/contracts/artifacts/contracts/rewards/RewardsManager.sol/RewardsManager.json`                      |
| L1GNS                 | `packages/contracts/artifacts/contracts/discovery/L1GNS.sol/L1GNS.json`                                      |
| Curation              | `packages/contracts/artifacts/contracts/curation/Curation.sol/Curation.json`                                 |
| L1Staking             | `packages/contracts/artifacts/contracts/staking/L1Staking.sol/L1Staking.json`                                |
| StakingExtension      | `packages/contracts/artifacts/contracts/staking/StakingExtension.sol/StakingExtension.json`                  |
| LibExponential        | `packages/contracts/artifacts/contracts/staking/libs/Exponential.sol/LibExponential.json`                    |
| HorizonStaking        | `packages/horizon/build/contracts/contracts/staking/HorizonStaking.sol/HorizonStaking.json`                  |
| GraphPayments         | `packages/horizon/build/contracts/contracts/payments/GraphPayments.sol/GraphPayments.json`                   |
| PaymentsEscrow        | `packages/horizon/build/contracts/contracts/payments/PaymentsEscrow.sol/PaymentsEscrow.json`                 |
| SubgraphService       | `packages/subgraph-service/build/contracts/contracts/SubgraphService.sol/SubgraphService.json`               |
| DisputeManager        | `packages/subgraph-service/build/contracts/contracts/DisputeManager.sol/DisputeManager.json`                 |
| AllocationHandler     | `packages/subgraph-service/build/contracts/contracts/libraries/AllocationHandler.sol/AllocationHandler.json` |

The horizon and subgraph-service paths are Hardhat outputs (`build/contracts`, mirroring the source tree), not Foundry's flat `build/`.

Library link placeholders (L1Staking → LibExponential; SubgraphService → AllocationHandler and others) encode the library's fully qualified source path. They stay stable as long as those libraries don't move; a later PR that moves a linked library must expect to update the reference and justify it in its description.

- [ ] **Step 1: Write the failing tests in `scripts/contracts-migration/check-bytecode.test.mjs`**

Use `node:test` and `node:assert/strict`. Write fixtures to a temp dir (`fs.mkdtempSync`). Constants:

- `META_A = 'a264697066735822' + '1220' + 'ab'.repeat(32) + '64736f6c63430007060033'`
- `META_B`: the same with `'cd'.repeat(32)`

Tests:

- `stripMetadata removes the CBOR blob`: `stripMetadata('0x6080' + META_A) === '6080'`.
- `stripMetadata keeps bytes after the blob`: `stripMetadata('0x6080' + META_A + 'ff'.repeat(32)) === '6080' + 'ff'.repeat(32)`.
- `stripMetadata leaves code without metadata unchanged`: `stripMetadata('0x6080') === '6080'`.
- `ignores metadata-only differences`:
  - artifact A `{bytecode:'0x6080'+META_A, deployedBytecode:'0x60aa'+META_A}`, artifact B the same with `META_B`;
  - `a = computeHashes({X: 'a.json'}, dir)` and `b = computeHashes({X: 'b.json'}, dir)`;
  - `compare(a.hashes, b.hashes)` deep-equals `[]`.
- `detects code differences`: as above, but B's `deployedBytecode` is `'0x60ab'+META_B`. `compare` deep-equals `['X: deployedBytecode differs']`.
- `detects differences after the metadata`: B's `bytecode` is `'0x6080'+META_B+'01'` versus A's `'0x6080'+META_A+'00'`. `compare` deep-equals `['X: bytecode differs']`.
- `rejects empty bytecode`: an artifact with `bytecode: '0x'`. `computeHashes(...).empty` deep-equals `['X']`.
- `fails when an artifact is missing`:
  - `computeHashes({X: 'nope.json'}, dir).missing` deep-equals `['nope.json']`;
  - spawning the CLI (`child_process.spawnSync(process.execPath, [script, '--root', dir, '--manifest', m, '--reference', r])`) exits with status 1, and stderr contains `nope.json`.
- `write refuses to produce a partial reference`: write a reference file with content `'{"keep":true}\n'`, then spawn the CLI with `--write` and a manifest containing a missing entry. It exits with status 1, and the reference file still reads `'{"keep":true}\n'`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `node --test 'scripts/contracts-migration/*.test.mjs'`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `check-bytecode.mjs` / `../lib/bytecode.mjs`.

- [ ] **Step 3: Implement `scripts/lib/bytecode.mjs` and `scripts/contracts-migration/check-bytecode.mjs` per the Interfaces block, and switch the compare script to the shared `stripMetadata`**

- [ ] **Step 4: Run the tests to verify they pass**

Run: `node --test 'scripts/**/*.test.mjs'`
Expected: all PASS, including the existing `scripts/verify-solhint-disables.test.mjs`.

- [ ] **Step 5: Check that the compare script still works**

The script refuses to compare identical paths, so give it a symlink:

```bash
ln -sfn "$PWD" /tmp/repo-link && node scripts/compare-repo-contract-bytecode-excluding-metadata.mjs . /tmp/repo-link
```

Expected: `FUNCTIONAL DIFFERENCES (0 contracts)`.

- [ ] **Step 6: Build and generate the reference**

Run: `pnpm build && pnpm check:bytecode --write && pnpm check:bytecode`
Expected: `reference.json` has 26 entries, each with two 64-hex-character hashes, and the check prints `OK: 26 contracts match`.

- [ ] **Step 7: Prove determinism**

Run: `pnpm clean && pnpm build && pnpm check:bytecode`
Expected: `OK: 26 contracts match`.

- [ ] **Step 8: Wire into CI**

Add the two steps to `.github/workflows/build-test.yml` as listed in Files.

- [ ] **Step 9: Commit and open PR**

```bash
git add scripts/lib/bytecode.mjs scripts/compare-repo-contract-bytecode-excluding-metadata.mjs scripts/contracts-migration package.json .github/workflows/build-test.yml
git commit -m "ci: add bytecode equivalence check for the contracts package migration"
```

PR description:

- Later move PRs update `manifest.json` paths only.
- `reference.json` hashes never change. Entries are removed only when their contract is deleted.
- The shared `stripMetadata` is now exact (it matches the full blob, not "everything to the end"). The repo comparison script is therefore slightly stricter: it no longer ignores the bytes some contracts have after the metadata in their creation bytecode.
- The onchain comparison for `legacy` and graph-token's mainnet contracts comes in Phase D (D2).

---

### Task 4 (PR 0d): Coverage baseline from `contracts-test`

**Files:**

- Create: `scripts/contracts-migration/summarize-coverage.mjs`
- Create: `scripts/contracts-migration/summarize-coverage.test.mjs`
- Create: `scripts/contracts-migration/coverage-baseline.json` (generated)

**Interfaces:**

- Produces `parseLcov(text: string): Record<string, { linesFound: number, linesHit: number, pct: number | null }>`:
  - Each record starts at `SF:` and ends at `end_of_record`.
  - The key is the `SF:` path from its **last** path segment that equals `contracts`. For example, `/home/runner/work/contracts/contracts/packages/contracts-test/contracts/rewards/RewardsManager.sol` becomes `contracts/rewards/RewardsManager.sol`. Paths that already start with `contracts/` are unchanged.
  - The values come from the record's `LF:` and `LH:` lines, with `pct = linesFound === 0 ? null : Math.round(linesHit / linesFound * 10000) / 100`.
- Produces a CLI: `node scripts/contracts-migration/summarize-coverage.mjs <lcov.info> <out.json>` writes `parseLcov` output with keys sorted, 2-space indent and a trailing newline. Later phases run the same parser on `forge coverage --report lcov` output.

- [ ] **Step 1: Write the failing tests in `summarize-coverage.test.mjs`**

- `parses one record with an absolute CI path`: `SF:/home/runner/work/contracts/contracts/packages/contracts-test/contracts/rewards/RewardsManager.sol`, `LF:200`, `LH:150`, `end_of_record` gives `{ 'contracts/rewards/RewardsManager.sol': { linesFound: 200, linesHit: 150, pct: 75 } }`.
- `keeps relative contracts paths`: `SF:contracts/upgrades/GraphProxy.sol` gives the key `contracts/upgrades/GraphProxy.sol`.
- `keeps records separate`: two records (`LF:10/LH:10` and `LF:4/LH:1`) give two keys with `pct` 100 and 25.
- `zero lines yields null pct`: `LF:0`, `LH:0` gives `pct: null`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `node --test 'scripts/contracts-migration/summarize-coverage.test.mjs'`
Expected: FAIL with `ERR_MODULE_NOT_FOUND`.

- [ ] **Step 3: Implement `parseLcov` and the CLI in `summarize-coverage.mjs`**

- [ ] **Step 4: Run the tests to verify they pass**

Run: `node --test 'scripts/**/*.test.mjs'`
Expected: all PASS.

- [ ] **Step 5: Run contracts-test coverage**

`scripts/coverage` does not create the address book that the sdk fixture needs; only `scripts/test` does. So run the regular tests first:

```bash
pnpm --filter @graphprotocol/contracts-tests test:self
pnpm --filter @graphprotocol/contracts-tests test:coverage:self
```

Expected: both complete. solidity-coverage writes to `packages/coverage/lcov.info`, because `.solcover.js` sets `istanbulFolder: '../coverage'`, even though its log says `./coverage/`. If it runs out of memory, retry with `NODE_OPTIONS=--max-old-space-size=8192`. Don't run `pnpm install` between the two commands; it can remove the address book again.

- [ ] **Step 6: Generate the baseline**

Run: `node scripts/contracts-migration/summarize-coverage.mjs packages/coverage/lcov.info scripts/contracts-migration/coverage-baseline.json`
Expected: the JSON has entries with `linesFound > 0` for at least these files:

- `contracts/rewards/RewardsManager.sol`
- `contracts/l2/discovery/L2GNS.sol`
- `contracts/discovery/GNS.sol`
- `contracts/l2/curation/L2Curation.sol`
- `contracts/governance/Controller.sol`
- `contracts/upgrades/GraphProxyAdmin.sol`
- `contracts/epochs/EpochManager.sol`
- `contracts/l2/gateway/L2GraphTokenGateway.sol`
- `contracts/gateway/L1GraphTokenGateway.sol`

No key contains `packages/`.

- [ ] **Step 7: Commit and open PR**

```bash
git add scripts/contracts-migration/summarize-coverage.mjs scripts/contracts-migration/summarize-coverage.test.mjs scripts/contracts-migration/coverage-baseline.json
git commit -m "test: record contracts-test line coverage baseline for the Foundry ports"
```

PR description:

- List the baseline line % for every file that will move to graph-core, graph-token and subgraph-discovery, and for EpochManager and RewardsManager. These are the parity targets from spec §4.
- Note that `.solcover.js` skips `contracts/arbitrum/` and `contracts/tests/`. L1ArbitrumMessenger, L2ArbitrumMessenger and AddressAliasHelper therefore have no baseline, and their parity is checked by the test mapping table only.
- Delete `packages/coverage/` locally after generating; it's not committed.
