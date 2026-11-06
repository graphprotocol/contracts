# Import billing-contracts into the monorepo

## Intent

`graphprotocol/billing-contracts` (Graph Studio billing: Billing, BillingConnector, BanxaWrapper) lives outside this monorepo only because it used to belong to a different GitHub organization. It has now moved to `graphprotocol`, so it comes into the monorepo as a new package. This is repository housekeeping: nothing about the contracts changes. The old repo is then marked deprecated and keeps its history.

## Goals

- A new private workspace package, `@graphprotocol/billing` in `packages/billing`, holding everything from billing-contracts `main` (`8b063db`), as is: contracts (including `contracts/arbitrum/` and `contracts/tests/`), tests, Hardhat deploy and ops tasks, `scripts/`, `utils/`, address books (`addresses.json`, `addresses-staging.json`), `hardhat.config.ts`, `tsconfig.json`, README and LICENSE.
- Contract source files are byte-identical to the originals, and the compiled bytecode equals the original repo's build, metadata hash ignored.
- The package builds and its tests run in the monorepo CI, like the other packages.
- One PR targeting `chore/contracts-removal-phase-0` (#1373), the branch going to audit. It joins the stack after Phase 2a (base head `dfc25afd`).
- The billing contracts are in the audit's scope. The PR merges into the base before the audit commit is fixed.
- The package stays operational: billing deployments and ops will be run from it once the original repo is deprecated. Its deploy and ops tasks and scripts work under pnpm, and the address books in `packages/billing` become the source of truth.

## Non-goals

- Keeping git history. One import commit; the history stays in the deprecated original repo.
- Publishing to npm. The package is `"private": true` with no changeset. The old npm name `graph-studio-billing-contracts` was never really published (npm shows only a `0.0.1-security` placeholder).
- Upgrading the toolchain or dependencies beyond what's needed to install, build and test in the monorepo.
- Integrating with `@graphprotocol/address-book`, toolshed, the `deployment` package or Ignition. Moving billing deployments into `packages/deployment` may come later as its own project.
- Deprecating the old repo. That's a manual GitHub step after the import lands.

## Anti-goals

- Any edit to a `.sol` file, or to the compiler settings: solc `0.8.16`, optimizer enabled, 200 runs, default EVM version.
- Reformatting imported files. Root `prettier`, `eslint`, `solhint` and `markdownlint` must not touch `packages/billing`. The precedent is `packages/legacy/verified/` in the root `.prettierignore`.
- Resolving a different OpenZeppelin or `arb-bridge-peripherals` version than the original lockfile. Those versions decide the bytecode.

## Constraints

- **Pinned contract dependencies:** the original `yarn.lock` resolves `@openzeppelin/contracts` to `4.7.3` and `arb-bridge-peripherals` to `1.0.11`. The package pins both exactly. The monorepo already holds OpenZeppelin 3.4.2 (graph-core alias) and 5.x elsewhere; pnpm keeps them per package.
- **Toolchain as in the original where it works:** Hardhat 2 (the lockfile has 2.11.2), ethers v5, typechain for ethers v5, mocha and chai, `hardhat-abi-exporter`, `solidity-coverage`. Change a version only if it fails to install or run on the monorepo's Node version, and record each change in the PR.
- **Repo-root files are not imported:** `yarn.lock`, `.husky/`, `commitlint.config.js`, `.github/`, and the package-level `.eslintrc`, `.eslintignore`, `.prettierrc.json`, `.prettierignore`, `.solhint.json`, `.solhintignore`, `lint-staged` config and `prepare`/husky script. The monorepo's root setup replaces them. `.example.env`, `.gitattributes`, `.gitignore` and `.solcover.js` come over if the package still uses them.
- **No secrets:** `scripts/test` contains a well-known ganache test mnemonic. That one is fine. Nothing else with keys or RPC URLs is added, and `hardhat.config.ts` keeps reading them from the environment.
- **Commits and PR:** conventional commits, no attribution lines. The PR is a draft on #1373's branch.

## Verification

- **Source:** every `.sol` file is byte-identical to `8b063db`, and so is every other imported file except `package.json` and the shell scripts in `scripts/` that call `yarn`. Those scripts change only as far as pnpm needs: `yarn <script>` becomes `pnpm <script>`, `yarn` (install) becomes `pnpm install`. A `diff -r` against a checkout of the original, excluding the dropped root files, shows only those changes, and the PR lists them.
- **Tasks:** every Hardhat task under `tasks/deployment` and `tasks/ops` loads (`npx hardhat --help` lists it). `deployAll` and each deploy task run on the in-process Hardhat network, or on a local `hardhat node` where the task needs one. `pullAll` and `addToMany` run against the contracts that deploy produced. Nothing touches a live network.
- **Bytecode:** build the original repo at `8b063db` with its own `yarn.lock` (in a scratch directory, not committed). Then compare, for every non-test contract, the monorepo build's `bytecode` and `deployedBytecode` with metadata stripped. The comparison is added to the existing `pnpm check:bytecode` (`scripts/contracts-migration/manifest.json` and `reference.json`), so CI keeps checking it.
- **Deployed code (informational):** compare runtime code with the address books' deployments of Billing on Arbitrum One, BillingConnector on mainnet and BanxaWrapper on Arbitrum One. Report the result in the PR without blocking on it. A deployment may predate `8b063db`.
- **Tests:** `pnpm --filter @graphprotocol/billing test:self` runs the original mocha suite on the in-process Hardhat network and passes with the original test count. The ganache gas-report mode (`RUN_EVM=true`) can stay as an unused script.
- **CI:** the package's `build`, `test:self` and `test:coverage:self` run in the existing `Build and Test` workflow through `pnpm -r`. Its coverage output is uploaded with the others.
- **Lint:** `pnpm lint` at the root leaves `git status` clean.

## Notes from the builder check

- The `Lint` workflow lints changed files, not root `pnpm lint`, so the exclusion has to cover `.github/workflows/lint.yml` too.
- `check:bytecode` fails on contracts with empty bytecode, so interfaces and the abstract `L1ArbitrumMessenger` stay out of the manifest.
- The original `scripts/test` always exits 0 (`result=0` after the run), so the original suite's pass count is confirmed by running `npx hardhat test` directly before it's used as the reference.

## Left to the builder

- How root lint is excluded: ignore files, glob changes or eslint config `ignores`.
- Which package scripts map to the monorepo conventions (`build`, `build:self`, `test`, `test:self`, `test:coverage:self`, `clean`, `lint`), and whether `scripts/build` and `scripts/test` are called or replaced with equivalent package.json scripts.
- The minimal toolchain fixes, within the constraints above.
- How the original reference build is produced and the hashes recorded, using the same hashing as `scripts/lib/bytecode.mjs`.
- Whether the root README's package table and `CLAUDE.md` get a line for the new package. Expected: yes, one line each.

## Calls made without explicit confirmation

- Package name `@graphprotocol/billing` and path `packages/billing`.
- The bytecode bar: equal to the original repo's build, the same bar as the frozen moves.
- Which repo-root files are dropped.
- Adding the billing contracts to `check:bytecode`.
- This document lives on the docs branch (#1372), next to the contracts-removal docs.
