# billing-contracts Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import `graphprotocol/billing-contracts` at `8b063db` into the monorepo as the private package `@graphprotocol/billing`, unchanged, building and tested in CI, with its deploy and ops tasks working under pnpm.

**Architecture:**

- One draft PR on `chore/contracts-removal-phase-0` (#1373, head `dfc25afd`) with two commits.
- The first commit is a verbatim copy of the kept files, plus the root lint exclusions that stop hooks from reformatting them. The second adapts the package to the monorepo.
- Task 1 produces the reference numbers in a scratch directory and commits nothing.

**Tech Stack:** pnpm workspaces, Hardhat 2, ethers v5, typechain (ethers-v5), mocha/chai, solc 0.8.16, OpenZeppelin 4.7.3, `arb-bridge-peripherals` 1.0.11, Node 24 (`.nvmrc`).

**Spec:** `docs/billing-import/design.md`.

## Global Constraints

- No `.sol` file and no compiler setting changes: solc `0.8.16`, optimizer enabled, 200 runs, default EVM version.
- `@openzeppelin/contracts` is pinned to `4.7.3` and `arb-bridge-peripherals` to `1.0.11`, exact versions.
- Every other dependency keeps the original's version, unless it fails to install or run on Node 24. Each change is recorded in the PR.
- The package is `"private": true`, with no changeset.
- Repo-root files are not imported: `yarn.lock`, `.husky/`, `commitlint.config.js`, `.github/`, `.eslintrc`, `.eslintignore`, `.prettierrc.json`, `.prettierignore`, `.solhint.json`, `.solhintignore`.
- Edits to imported files are limited to:
  - `package.json`;
  - in `scripts/`, `yarn <script>` becomes `pnpm <script>`, `yarn` (install) becomes `pnpm install`, and `yarn clean:all` becomes `pnpm clean:all`.
- Root lint never touches `packages/billing`. This covers root `pnpm lint`, root `lint-staged`, `.github/workflows/lint.yml` in both `changed` and `all` modes, and `pnpm -r` solhint runs.
- No RPC URL or API key is written to any file, commit, log or PR. RPC URLs are passed only as inline env vars. The ganache test mnemonic already in `scripts/test` is the only key material, and it stays as it is.
- Conventional commits, with no Co-Authored-By line and no AI attribution. Never `git stash`. Push or open the PR only when the controller says so.
- Smoke tests never touch a live network. Deploy tasks write only to a scratch copy of the address book.

## Review Focus

1. **A root hook silently reformats imported files.** lint-staged runs on every commit, so the source check in Task 3 (`diff -r` after both commits) must show only the allowed edits.
2. **pnpm resolves a different OpenZeppelin or arb-bridge version than yarn did.** The bytecode check fails, and it is pinned in `check:bytecode` (Task 3).
3. **The original `scripts/test` hides failures.** It sets `result=0` before exit. Task 1 gets the pass count from `npx hardhat test` directly, and `test:self` must fail when a test fails (Task 3, Step 6).
4. **A task loads only when `SKIP_LOAD` is unset,** so `build` passing proves nothing about the tasks. Task 3's smoke run lists and runs them.
5. **CI's solhint loop (`pnpm -r exec ... if [ -d contracts ]`) picks up billing.** Task 2 excludes it, and Task 2, Step 4 checks `lint.yml` in `all` mode locally.

---

### Task 1: Reference build of the original (no commit)

**Files:** scratch only: `<scratch>/billing-ref/` (clone) and `<scratch>/billing-ref.json` (results).

**Interfaces:**

- Produces `<scratch>/billing-ref.json` with these fields:
  - `hashes`: for each non-test contract with non-empty bytecode, `bytecodeHash` (from `scripts/lib/bytecode.mjs`) of `bytecode` and `deployedBytecode`;
  - `tests`: the passing count;
  - `deployed`: for each address-book deployment checked, whether the runtime code matches with metadata stripped.
- Contracts in `hashes`: `Billing`, `BillingConnector`, `BanxaWrapper`, plus any other contract under `contracts/` (not `contracts/tests/`) whose bytecode is non-empty. Interfaces and the abstract `L1ArbitrumMessenger` are excluded.

- [ ] **Step 1:** Clone `https://github.com/graphprotocol/billing-contracts` into scratch and check out `8b063db`. Run `yarn install --frozen-lockfile` with corepack yarn 1 on Node 18, through `npx -p node@18` or similar; Node 24 is acceptable only if it works. Then run `SKIP_LOAD=true npx hardhat compile`. Expected: exit 0.
- [ ] **Step 2:** Run `SKIP_LOAD=true npx hardhat test`. Record the passing count. Expected: 0 failing. If any fail, stop and report.
- [ ] **Step 3:** Compute the hashes with `node -e` importing `<repo>/scripts/lib/bytecode.mjs` over `build/artifacts/contracts/**/<Name>.json`, and write `billing-ref.json`.
- [ ] **Step 4: Deployed code, informational.** Fetch runtime code with `cast code <address> --rpc-url "$RPC"`, with `RPC` given inline. Check Billing (`0x1B07D3344188908Fb6DEcEac381f3eE63C48477a`) and BanxaWrapper (`0xc9E1Aa57223aDD21cC88A03088aF552f1ea8A34a`) on Arbitrum One, and BillingConnector (`0x8017B9AF3F199CC6b08A48DA3859410F20bbea72`) on mainnet. Compare with `deployedBytecode`, metadata stripped and immutables masked if any. Record match or mismatch. No step blocks on this.

### Task 2: Verbatim import and lint exclusions (commit 1)

**Files:**

- Create: `packages/billing/**`, copied byte-for-byte from `8b063db`, minus the root files listed in Global Constraints. It includes `package.json` as is.
- Modify: root `.prettierignore`, `.solhintignore`, `eslint.config.mjs` (global `ignores`), markdownlint ignore (`.markdownlintignore`, or the `lint:md` ignore path), `.github/workflows/lint.yml`, and `scripts/lint-staged-run.sh` or the `lint-staged` globs.

**Interfaces:**

- Produces the exclusion glob `packages/billing/`, used the same way as `packages/legacy/verified/` today.

- [ ] **Step 1:** Create the worktree `../worktrees-contracts/billing-import` on the new branch `feat/billing-import`, from `origin/chore/contracts-removal-phase-0`. Run `pnpm install --frozen-lockfile`.
- [ ] **Step 2:** Add the exclusions:
  - `packages/billing/` in `.prettierignore` and `.solhintignore`, plus `'packages/billing/**'` in eslint's global `ignores`;
  - in markdownlint;
  - in `lint.yml`: every `CHANGED_*` filter, the `all`-mode `git ls-files` lists, and the `pnpm -r exec` solhint loop (skip the package by directory);
  - in lint-staged: files under `packages/billing/` pass through untouched.
- [ ] **Step 3:** Copy the files with `git -C <scratch>/billing-ref archive 8b063db | tar -x -C packages/billing`, then delete the excluded root files.
- [ ] **Step 4:** Verify before committing. Commit 1 adds a workspace package that the lockfile doesn't know, with the original `package.json` (its `lint:*` and `prepare` scripts). So it doesn't install or build, and the PR says so, as port PRs did. Root `pnpm lint` (which runs `pnpm -r run lint:sol`) is checked in Task 3. Here, run the file-level linters directly:
  - `pnpm lint:ts`, `pnpm lint:md`, `pnpm lint:json`, `pnpm lint:yaml` and `npx prettier -w --cache --log-level warn 'packages/**/*.sol'`, then `git status --porcelain packages/billing`. Expected: empty.
  - The `lint.yml` `all`-mode file lists, run locally. Expected: no `packages/billing` path.
  - `diff -r <scratch>/billing-ref packages/billing`, excluding `.git`, `node_modules`, `build`, `cache` and the dropped files. Expected: no differences.
- [ ] **Step 5:** Commit `chore(billing): import billing-contracts at 8b063db`. Then rerun the Step 4 `diff -r`. Expected: still no differences. This proves lint-staged left the files alone.

### Task 3: Adapt to the monorepo (commit 2)

**Files:**

- Modify: `packages/billing/package.json`, and `packages/billing/scripts/{build,test,coverage,deployAll,prepublish,security}`, the `yarn` lines only.
- Modify: `scripts/contracts-migration/{manifest,reference}.json`, root `README.md` (package table), root `CLAUDE.md` (package list), `pnpm-lock.yaml`.

**Interfaces:**

- Consumes `billing-ref.json` (Task 1).
- Produces these `package.json` scripts:
  - `build` = `pnpm build:self`;
  - `build:self` = `SKIP_LOAD=true scripts/build`;
  - `test` = `pnpm build && pnpm test:self`;
  - `test:self`, which runs the mocha suite and exits non-zero on failure;
  - `test:coverage` and `test:coverage:self`, which write `coverage/coverage-final.json` so the CI upload step finds it;
  - `clean`;
  - `deploy:all` = `scripts/deployAll`;
  - and the original `compile`, `flatten`, `typechain` and `verify`.

  The package has no `lint*` script and no `prepare` script.

- [ ] **Step 1: `package.json`.**
  - Set the name to `@graphprotocol/billing`, add `"private": true`, and keep the version `1.1.0`.
  - Pin `@openzeppelin/contracts` to `4.7.3` and `arb-bridge-peripherals` to `1.0.11`.
  - Drop `husky`, `lint-staged`, `@commitlint/*`, `eslint*`, `prettier*`, `solhint*` and the `lint-staged` block.
  - Add the scripts listed under Interfaces.
  - Run `pnpm install`. Then check that `node -p "require('@openzeppelin/contracts/package.json').version"`, run in the package, prints `4.7.3`.
- [ ] **Step 2: `scripts/` edits**, as Global Constraints allow. `scripts/test` keeps `result=0`, because it is imported unchanged. `test:self` is therefore `SKIP_LOAD=true hardhat test`, not `scripts/test`.
- [ ] **Step 3: Minimal toolchain fixes.** Run `pnpm --filter @graphprotocol/billing build`. Expected: exit 0. Fix install or run failures only by changing dependency versions in `package.json` or adding missing devDependencies such as `ganache-cli`, `ts-node` or `@types/*`. Record each change with its reason. If a fix needs an edit to `hardhat.config.ts`, `tsconfig.json`, a task or a test, stop and report.
- [ ] **Step 4: Bytecode.**
  - Add each contract in `billing-ref.json` `hashes` to `manifest.json` as `"<Name>": "packages/billing/build/artifacts/contracts/<path>/<Name>.sol/<Name>.json"`.
  - Add its hashes to `reference.json`, keeping keys sorted. Copy them from Task 1; never `--write`.
  - Run `pnpm check:bytecode`. Expected: `OK: <18 + N> contracts match`.
- [ ] **Step 5: Tests.** Run `pnpm --filter @graphprotocol/billing test:self`. Expected: the same passing count as Task 1, 0 failing.
- [ ] **Step 6: Failure check.** Temporarily break one assertion, then run `test:self`. Expected: non-zero exit. Revert.
- [ ] **Step 7: Coverage.** Run `pnpm --filter @graphprotocol/billing test:coverage:self`. Expected: exit 0, and `packages/billing/coverage/coverage-final.json` exists.
- [ ] **Step 8: Task smoke run**, on a local `npx hardhat node` with its default accounts and a scratch copy of `addresses.json` (`ADDRESS_BOOK=<scratch>/addresses.json`, chainId 1337 entries added there).
  - `npx hardhat --help` lists every task in `tasks/deployment` and `tasks/ops`.
  - `deploy-token`, then `deploy-billing` (collector, token and gateway from the local accounts or mock deployments), `deploy-billing-connector` (with `L1TokenGatewayMock` and `InboxMock` from `contracts/tests`), `configure-billing` and `deploy-banxa` run, each with `--network localhost`. Expected: exit 0, with addresses written to the scratch book.
  - `ops:add-to-many --dry-run`, then without `--dry-run`, with a two-entry depositors file in scratch. Expected: exit 0, and `Billing.userBalances` reflects the deposits.
  - `ops:pull-all` needs the billing subgraph, whose default URL is the retired hosted service, so only `--help` is run. The PR notes the dead default URL.
  - `deployAll` isn't run end to end, because it needs two networks and mnemonics. `bash -n scripts/deployAll` must exit 0. Report how far a local run gets.
- [ ] **Step 9: Docs.** Add one line for `@graphprotocol/billing` in the root README package table and in `CLAUDE.md`'s package list.
- [ ] **Step 10: Source check.** Run `diff -r <scratch>/billing-ref packages/billing`, with Task 2's exclusions. Expected: only `package.json` and the `yarn` lines in `scripts/`.
- [ ] **Step 11: Commit** `chore(billing): build and test in the monorepo`.
- [ ] **Step 12: Verification.**
  - `pnpm -r --sequential run build`, `pnpm test:scripts`, `pnpm check:bytecode` and `pnpm -r --sequential run test:self` all exit 0.
  - `pnpm lint`, then `git status --porcelain`. Expected: clean.
  - Rerun Step 10's `diff -r`. Expected: the same result.

## PR description

The PR description says:

- the two-commit structure, and that auditors read commit 1 as the original code and commit 2 as monorepo glue;
- the source `diff -r` result;
- the bytecode result and the deployed-code comparison;
- the test counts;
- every dependency version change, with its reason;
- the smoke-run results;
- the dead hosted-service URL in `ops:pull-all`.
