# Removing `packages/contracts` — Design

Status: draft for review (revision 3, after two review passes)
Date: 2026-10-22

## Goal

Delete `packages/contracts` (`@graphprotocol/contracts`) and `packages/contracts-test` from the monorepo. Every contract that is still in use moves to the package that owns its domain, and its unit tests are rewritten in Foundry in that package. Dead code is deleted. Nothing changes onchain: moves are mechanical and must produce identical bytecode, ignoring the metadata hash.

Out of scope:

- Porting contracts to Solidity 0.8.
- Any change to contract behaviour.
- Bringing `billing-contracts` into the monorepo. That is a separate sub-project with its own spec.

## Decisions

### 1. npm

- `@graphprotocol/contracts` is frozen at 7.3.0, marked deprecated with `npm deprecate`, and never published again. The git tag `@graphprotocol/contracts@7.3.0` preserves its source, CHANGELOG and docs (`DEPLOYMENT.md`, `TESTING.md`).
- horizon's and subgraph-service's Ignition modules stay as the record of how Horizon was deployed. They read their artifacts from the published 7.3.0 through an npm alias (§5).
- `@graphprotocol/sdk` is already deprecated in its README (which points to `@graphprotocol/toolshed`). It also gets `npm deprecate`.
- Known external consumers (graph-network-subgraph, subgraph-studio, network-monitor) pin old versions and are migrated as needed. Addresses come from `@graphprotocol/address-book`, ABIs from `@graphprotocol/interfaces`.

### 2. Package layout

Final dependency graph (arrow = "depends on"):

```
graph-core          → interfaces
graph-token         → graph-core, interfaces
subgraph-discovery  → graph-token, graph-core, interfaces
issuance            → graph-core, interfaces
toolshed            → issuance                         (exists today)
horizon             → subgraph-discovery, graph-token, graph-core, issuance, toolshed, interfaces
subgraph-service    → horizon, subgraph-discovery, graph-token, graph-core, toolshed, interfaces
testing             → graph-core, horizon, issuance, subgraph-service, interfaces
deployment          → graph-core, graph-token, subgraph-discovery, issuance, horizon, subgraph-service

legacy              (new, private, no workspace dependencies)
```

Rules that keep this acyclic:

- `issuance` depends on `graph-core` and `interfaces` only. Its code and tests never use horizon, subgraph-discovery or graph-token, because `horizon → toolshed → issuance` already exists.
- The 0.7.6 packages (`graph-core`, `graph-token`, `subgraph-discovery`) do not use `toolshed` or `hardhat-graph-protocol`. They have their own small Hardhat configs. `legacy` has no Hardhat config.

| Package              | Contracts                                                                                                                                                                                                             | Compiler                 |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------ |
| `graph-core`         | Controller, Governed, Pausable, Managed, GraphProxy, GraphProxyAdmin, GraphProxyStorage, GraphUpgradeable                                                                                                             | solc 0.7.6 only (see §3) |
| `graph-token`        | GraphToken (mainnet), L2GraphToken, GraphTokenUpgradeable, TokenUtils, GraphTokenGateway (base), L1GraphTokenGateway, L2GraphTokenGateway, BridgeEscrow, L1ArbitrumMessenger, L2ArbitrumMessenger, AddressAliasHelper | solc 0.7.6 only          |
| `subgraph-discovery` | L2GNS, L2GNSStorage, GNS, GNSStorage, L2Curation, CurationStorage, GraphCurationToken, SubgraphNFT, SubgraphNFTDescriptor, HexStrings, Base58Encoder, Multicall                                                       | solc 0.7.6 only          |
| `horizon`            | EpochManager, EpochManagerStorage (in `contracts/legacy-0.7/`)                                                                                                                                                        | mixed                    |
| `issuance`           | RewardsManager, RewardsManagerStorage, MathUtils (in `contracts/legacy-0.7/`)                                                                                                                                         | mixed                    |
| `legacy`             | Verified source of the seven mainnet implementations (see "legacy package" below)                                                                                                                                     | solc 0.7.4 and 0.7.6     |

Why `subgraph-discovery` is its own package:

- These contracts need OpenZeppelin 3.4.2 under its real name. `ISubgraphNFT` and `IGraphCurationToken` in `@graphprotocol/interfaces` import `@openzeppelin/contracts/token/ERC721/IERC721.sol` and `@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol`. Inside horizon or subgraph-service (Hardhat 2, OpenZeppelin 5), those imports resolve to v5 and fail. An alias cannot fix imports inside `interfaces`.

Deleted, with no replacement:

- Staking: L2Staking. The Arbitrum proxy now runs HorizonStaking.
- AllocationExchange, EthereumDIDRegistry, SubgraphAvailabilityManager.
- The Arbitrum DisputeManager and ServiceRegistry, along with their storage contracts.
- Mocks under `contracts/tests/` that no ported test needs: ArbSysMock, `tests/ens/*`, LegacyGNSMock, MockERC165, MockSubgraphService, and both L1GraphTokenLockTransferTool mocks.
- Each mainnet-only contract is deleted from `packages/contracts` only after its verified source exists in `legacy`.

#### legacy package

- A frozen, private archive of the source that actually runs on mainnet, for GraphToken, L1GraphTokenGateway, BridgeEscrow, L1GNS, Curation, L1Staking and StakingExtension.
- Current source reproduces only Curation. GraphToken was built with solc 0.7.4, and nine files shared between the implementations, including `Managed.sol`, differ from one implementation to the next. One shared source tree can't hold them, so each contract has its own bundle.
- Each bundle is `verified/<Contract>/`: the Sourcify-verified sources, unchanged, with the compiler version and settings. All seven were compiled locally and reproduce mainnet, ignoring metadata and immutable values. L1Staking's linked library address comes from its settings, so it is part of the check.
- It has no Solidity imports from the workspace, no Hardhat config and no tests of contract behaviour. Formatters and linters must not touch `verified/`.
- `test:self` checks every source file against a committed hash, compiles every bundle with its exact compiler (solc-js from npm) and compares the result with the hash of the on-chain code committed in `mainnet.json`, so CI needs no RPC secret. Recording those hashes needs an RPC URL once. The source hashes are needed because comments and formatting don't change bytecode. GraphToken and L1Staking are Sourcify partial matches, so their sources may differ from the deployed ones outside the code.
- graph-token keeps its current source for GraphToken, L1GraphTokenGateway and BridgeEscrow, and its README says this is not the code running on mainnet.
- Historical audit reports from `packages/contracts/audits/` (29 PDFs) move to `packages/legacy/audits/`.

### 3. Compiler: keep 0.7.6, port only when upgrading

Contracts move unchanged, so moving them changes no bytecode. For mainnet-only implementations, the record of what is deployed is `legacy`, not the package that holds the current source. A contract is ported to 0.8 only when it gets a real upgrade, and the port ships and is audited together with that upgrade. Some contracts are not upgradeable and stay 0.7.6 forever:

- GraphToken (mainnet)
- Controller
- GraphProxyAdmin
- SubgraphNFT
- GraphCurationToken (the clone master)

The 0.7.6 settings must reproduce the current build exactly: solc 0.7.6, optimizer enabled, 200 runs, no `evmVersion`, no `viaIR`, default metadata. Everything else follows from that.

#### graph-core, graph-token and subgraph-discovery

- Each has a single Hardhat compiler: 0.7.6 with the settings above.
- graph-token and subgraph-discovery depend on OpenZeppelin `contracts` and `contracts-upgradeable` 3.4.2 under their real names.
- graph-core has no OpenZeppelin imports of its own. It only reaches `IERC20` through `IGraphToken`, so it depends on OpenZeppelin `^5.4`, whose `IERC20` uses `>=0.4.16`. That keeps graph-core importable from 0.7.6 code, 0.8 code and 0.8 Foundry tests. (EpochManager, RewardsManager and L2GNS were verified to produce identical bytecode with v5's `IERC20`.)
- `packages/deployment` always uses these packages' own 0.7.6 artifacts. That includes GraphProxy, GraphProxyAdmin and Controller, which are deployed from 0.7.6 builds. Ignition uses the 7.3.0 artifacts (§5).
- The graph-core files keep the dual pragma `^0.7.6 || ^0.8.27`, so 0.8 code can import them as source. Managed moves from `^0.7.6` to that dual pragma; it was verified to compile under 0.8.35.
- graph-token adds `arbos-precompiles` (needed by L2ArbitrumMessenger).
- `TokenUtils` (in graph-token) also keeps its dual pragma. It is imported as source by 0.8 code in horizon (HorizonStaking, GraphPayments, PaymentsEscrow) and subgraph-service (SubgraphService, DisputeManager, AllocationManager, AllocationHandler).

#### horizon and issuance (mixed)

- Moved files live under `contracts/legacy-0.7/`.
- OpenZeppelin 3.4.2 is installed as the npm aliases `@openzeppelin/contracts-v3` and `@openzeppelin/contracts-upgradeable-v3`. The moved files' own OpenZeppelin imports are rewritten to those aliases (SafeMath, IERC165).
  - The aliased upgradeable package never imports `@openzeppelin/contracts` internally, so the alias is safe.
  - In horizon (Hardhat 2, which resolves every import from the project root), EpochManager reaches `IERC20` through `IGraphToken` and gets horizon's OpenZeppelin 5 `IERC20` (`>=0.4.16`). This was verified to compile with identical bytecode. horizon's `@openzeppelin/contracts` floor goes from `^5.0.2` to `^5.4.0`, because that pragma depends on it.
  - In issuance (Hardhat 3, which resolves imports per package), `IGraphToken` inside `interfaces` probably resolves to interfaces' own OpenZeppelin 3.4.2. That's fine for the 0.7.6 RewardsManager, but step 5 must confirm it with a real build. Rule: issuance's 0.8 code never imports graph-core's Managed or graph-token's TokenUtils. (issuance already has its own `contracts/common/IGraphToken.sol`.)
- Hardhat:
  - horizon (Hardhat 2 with the toolshed base config) gets `solidity.compilers: [<existing 0.8 settings>, <0.7.6 settings>]`. Hardhat 2 has no per-folder override; it selects 0.7.6 from the `^0.7.6` pragma.
  - issuance (Hardhat 3, `issuance/hardhat.base.config.ts`) adds a 0.7.6 entry next to its existing 0.8 compiler.
  - The 0.7.6 entry must not inherit `viaIR` or `evmVersion: cancun`.
- Foundry: `skip = ["contracts/legacy-0.7/**"]`. `lint:forge`, solhint and prettier also ignore `legacy-0.7/`.
- CI rule: no file outside `legacy-0.7/` may import the `-v3` aliases (grep check).
- horizon already has its own `Managed` (`contracts/staking/utilities/Managed.sol`). Consumers must refer to graph-core's Managed by its fully qualified name in artifacts and typechain.

### 4. Tests

- `packages/contracts-test` is deleted. Each package owns its unit tests, written in **Foundry**, following the existing suites in horizon, subgraph-service and issuance:
  - a shared base test contract (`GraphBase.t.sol`, `SubgraphBaseTest.t.sol`);
  - `shared/` helpers and `mocks/`;
  - the same directory layout, naming and fuzzing style.

  Each new package copies the conventions of its nearest neighbour.

- Tests are written **before** the contracts move (Phase T):
  - Test files are 0.8, because forge-std needs `>=0.8.13`. They never import 0.7.6 source.
  - They deploy the contracts under test from compiled artifacts:
    - **Before the move:** the Hardhat JSON in `@graphprotocol/contracts/artifacts`, read with `vm.readFile` + `vm.parseJsonBytes(".bytecode")` and deployed with `create`. `packages/testing/test/harness/RealRewardsHarness.t.sol` is the template.
    - **After the move:**
      - In graph-core, graph-token and subgraph-discovery, Foundry compiles the 0.7.6 sources itself (it handles several solc versions), and tests switch to `deployCode("X.sol:X")` so coverage registers.
      - In horizon and issuance, tests keep reading the package's own Hardhat artifact under `legacy-0.7/`.
  - Tests interact through interfaces they can compile under 0.8:
    - In graph-core and in OpenZeppelin-5 packages (horizon, issuance), they use `@graphprotocol/interfaces`.
    - In graph-token and subgraph-discovery (OpenZeppelin 3.4.2), `IGraphToken`, `ISubgraphNFT` and `IGraphCurationToken` can't be imported from 0.8. Tests there use local minimal interfaces or OpenZeppelin 5's `IERC20` from a test-only remapping.
  - Mocks are 0.8 contracts in the test tree. If a mock needs a 0.7.6 base, it is deployed from an artifact instead.
  - Each package lists its artifact folders explicitly in `foundry.toml` `fs_permissions`, because pnpm symlinks point outside the package.
  - `forge test` depends on Hardhat artifacts, so each package's `test` script builds first. That already holds where `test` runs `pnpm build`.
- **Shared fixture.** Upgradeable contracts have an `onlyImpl` `initialize`, so they must sit behind a GraphProxy and be activated through GraphProxyAdmin `upgrade` + `acceptProxyAndCall`. Each package's base test contract has a small helper that:
  - deploys Controller and GraphProxyAdmin from graph-core's artifacts;
  - unpauses the protocol (the Controller constructor leaves it paused);
  - registers mocks with `setContractProxy` and calls `syncAllContracts`;
  - deploys the contract under test behind a proxy.

  Contract-specific setup the ports must reproduce:
  - **L2GNS:** SubgraphNFT (minter and descriptor set), a real L2Curation with a GraphCurationToken master, an L2GraphToken with a minter, and a registered L2 gateway.
  - **L2Curation:** `setSubgraphService` before `collect`.
  - **L2GraphTokenGateway:** `vm.mockCall` / `vm.etch` at ArbSys `0x64`.

- **Unit tests use mocks, not the full network.** A test deploys only the contract under test plus mocks for its dependencies. Issuance tests in particular mock EpochManager, Curation, Staking, GRT and the subgraph service, and never load artifacts from horizon or subgraph-discovery (see the acyclicity rules in §2). The old rewards tests that went through legacy Staking (restaking, rewards destination, delegation cut) keep their RewardsManager assertions as mock-based unit tests. Their Staking assertions are dropped: that is legacy Staking behaviour, and the Horizon equivalent is already tested in subgraph-service. `packages/testing` stays the home for new cross-package flows.
- **Coverage.** Phase 0d records per-contract **line** coverage from `contracts-test` (solidity-coverage) before anything changes. Branch numbers aren't comparable between solidity-coverage and `forge coverage`, so they're informative only.
  - In graph-core, graph-token and subgraph-discovery, `forge coverage` line coverage after the move must be at least the baseline.
  - EpochManager and RewardsManager live in Foundry-skipped `legacy-0.7/` folders, so Foundry can't measure coverage for them. For those two, completeness is enforced by the old-to-new test mapping table.

#### Test assignment

| Destination        | Source tests (`contracts-test/tests/unit`)                                                                                                                | Approx. lines |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- |
| issuance           | `rewards/*` except `subgraphAvailability.test.ts`                                                                                                         | 6.8k          |
| subgraph-discovery | `l2/l2GNS.test.ts`, `l2/l2Curation.test.ts`, `lib/gnsUtils.ts`                                                                                            | 1.8k          |
| graph-token        | `gateway/*`, `l2/l2GraphToken.test.ts`, `l2/l2GraphTokenGateway.test.ts`, `l2/l2ArbitrumMessengerMock.ts`, `graphToken.test.ts`, `lib/graphTokenTests.ts` | 1.6k          |
| graph-core         | `governance/*`, `upgrade/admin.test.ts`                                                                                                                   | 0.5k          |
| horizon            | `epochs.test.ts`                                                                                                                                          | 0.2k          |

Notes:

- Today `l2GNS.test.ts` stakes and allocates through L2Staking. Its port uses a staking mock instead.
- `controller.test.ts`, `pausing.test.ts` and `admin.test.ts` use EpochManager, Staking and Curation. Their ports use Managed or GraphUpgradeable mocks instead.
- `l2GraphTokenGateway.test.ts` uses RewardsManager. Its port uses a plain callhook receiver mock.
- `lib/gnsUtils.ts` is also imported by `gns.test.ts`, which is dropped but stays until D1. T3 deletes `gns.test.ts` together with `gnsUtils.ts`.

Dropped, because their contracts are deleted or legacy:

- `gns.test.ts`: it tests L1GNS and is already `describe.skip`.
- `curation/*` (L1 Curation), `disputes/*`, `payments/*`, `serviceRegisty.test.ts`.
- `staking/*`, `l2/l2Staking.test.ts`, `rewards/subgraphAvailability.test.ts`.

#### Mocks needed by ported tests

| Mock                                                                                 | Destination                                                                             |
| ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------- |
| GovernedMock, ManagedMock (new, 0.7.6)                                               | graph-core                                                                              |
| BridgeMock, InboxMock, OutboxMock, CallhookReceiverMock, TokenUtilsMock (new, 0.7.6) | graph-token                                                                             |
| MockIssuanceAllocator, MockRewardsEligibilityOracle                                  | issuance (reuse its existing 0.8 mocks where they exist; otherwise rewrite them in 0.8) |

ManagedMock and TokenUtilsMock are added to `packages/contracts/contracts/tests/` in Phase T, because 0.8 tests can't compile a Managed contract or call the TokenUtils library. They move with their packages in Phase 1. ArbSysMock is not used (ArbSys is faked with `vm.mockCall`), so it stays on the delete list.

Every test-port PR includes a table mapping each old test case to its new Foundry test, or to "dropped" with a reason.

### 5. Tooling and infrastructure

#### Ignition

Ignition deployed Horizon, but new deployments go through `packages/deployment`. The Ignition modules and journals stay as the record of that deployment, with one mechanical change to their imports.

- horizon and subgraph-service import 14 artifacts in 15 module files from `@graphprotocol/contracts/artifacts/...`. Each package's `tasks/deploy.ts` imports the modules, and `loadTasks` loads it in every built Hardhat run. Both tsconfigs also include `ignition/**/*.ts`. The imports must therefore keep resolving after the workspace package loses those artifacts.
- Both packages can't simply pin `@graphprotocol/contracts` to 7.3.0. Their Solidity imports from it still need the workspace version until Phase 1: the published sources use the pragma `^0.7.6 || 0.8.27`, and these packages compile with 0.8.35.
- Before D3, both packages add the devDependency `"@graphprotocol/contracts-7.3.0": "npm:@graphprotocol/contracts@7.3.0"`, and the module imports change only the package name to `@graphprotocol/contracts-7.3.0`. The tarball ships every imported artifact. Journals and module logic don't change.
- Their `@graphprotocol/contracts` workspace dependency stays for Solidity imports and is removed in Phase 1 as usual.
- The modules now hold 7.3.0 bytecode. It differs from current source for RewardsManager, L2GNS and L2Curation. `test:integration`, which runs the modules on a fork and isn't in CI, therefore deploys those 7.3.0 versions.

#### Verification and scripts

- `horizon/scripts/pre-verify`, `subgraph-service/scripts/pre-verify` and `horizon/tenderly.config.json` `externalArtifacts` read `../contracts/artifacts` for verifying Ignition deployments. They switch to the 7.3.0 alias with the modules, so they keep matching the bytecode the modules deploy.
- issuance's artifacts are Hardhat 3 format (`hh3-artifact-1`). Step 5 confirms that `packages/deployment` and verification work with them. If not, the fix is to ship a Hardhat 2-shaped copy of the RewardsManager artifact from issuance.

#### `packages/deployment`

- The `'contracts'` artifact source is replaced by one source per package: `graph-core`, `graph-token`, `subgraph-discovery`, `issuance`, `horizon`. This touches:
  - `lib/artifact-loaders.ts`, `lib/contract-registry.ts`, `lib/deploy-implementation.ts`, `lib/deployment-validation.ts`
  - `scripts/generate-abis.ts`, `test/bytecode-comparison.test.ts`
  - `docs/Design.md`, and the `package.json` dependency and `build:clean` script
- `tasks/verify-contract.ts` gets cases for the new packages and supports nested source paths (`contracts/legacy-0.7/...`). Each new package has a Hardhat config with `hardhat-verify`.

#### `packages/testing`

- Imports switch to `graph-core`.
- The RewardsManager artifact path moves to issuance (`artifacts/contracts/legacy-0.7/...`), along with `foundry.toml` `fs_permissions`.
- The PR checks that `RealRewardsHarness` loads the real RewardsManager. Today it silently falls back to a mock if the artifact is missing.

#### Removed tooling and CI

- `packages/contracts/task` (`@graphprotocol/contracts-task`, the old sdk-based ops tooling) is deleted, not ported. `packages/deployment` replaces it.
- `.github/workflows/verifydeployed.yml` is deleted. It depends on contracts-task.
- `publish.yml` drops `contracts` and adds `graph-core`, `graph-token` and `subgraph-discovery`.
- The root `lint:yaml` drops `packages/contracts/task/config`.
- `count-patterns.txt` paths are updated.
- `@graphprotocol/sdk` is removed from the `pnpm-workspace.yaml` catalog and from `minumumReleaseAgeExclude` (the key's real, misspelled name).
- `build-test.yml` coverage collection is updated for the removed packages and the new ones.
- The Docker image (`Dockerfile`, `publish-image.yml`) is checked for use of `packages/contracts` or the sdk before deletion.

#### token-distribution

- Its three tests that import `Staking` / `Staking__factory` switch to an interface from `@graphprotocol/interfaces` or a local mock.
- The `@graphprotocol/contracts` dependency is removed.

#### address-book

Address books are copied from each package into `address-book/src/<name>/addresses.json`, tracked as regular files, and listed in `address-book/scripts/sources.js`.

- New `packages/legacy/addresses.json` with every L1 entry from `packages/contracts/addresses.json`:
  - mainnet (1) and Sepolia (11155111);
  - including Controller, EpochManager, RewardsManager, DisputeManager, ServiceRegistry, GraphProxyAdmin and SubgraphNFT. It is the L1 deployment record, even for contracts whose source isn't in `legacy`.
- `'legacy'` is added to `sources.js`.
- GraphCurationToken and SubgraphNFTDescriptor (live on Arbitrum One and Arbitrum Sepolia, today only in `packages/contracts/addresses.json`) are added to `horizon/addresses.json`.
- L2 token and gateway entries stay in `horizon/`, where they are today.
- Dropped:
  - Goerli (5) and Arbitrum Goerli (421613);
  - Arbitrum entries for deleted contracts;
  - `arbitrum-addresses.json` (Arbitrum bridge infra, used only by the sdk);
  - `addresses-staging.json` and `addresses-local.json`.

#### Publishing

`graph-core`, `graph-token` and `subgraph-discovery` follow issuance's package setup:

- `files`: contracts, artifacts, types and README
- `license: GPL-2.0-or-later`
- starting version 1.0.0
- an initial changeset

horizon and subgraph-service add the new packages as devDependencies, the same way they list `@graphprotocol/contracts` today. They publish build output only. `legacy` is `"private": true`.

#### Docs and references updated

- Root `CLAUDE.md`, `README.md` and `.gitignore`.
- `docs/IGraphProxyAdminInterfaceFix.md`, `docs/ForgeLintSymlinkIssue.md`, `docs/Linting.md`.
- `issuance/docs/testing/reo/*TestPlan.md`.
- toolshed's `src/deployments/{horizon,subgraph-service}/contracts.ts` comments.

## PR sequence

Tests are ported first, against the contracts where they are today. Then dead code and the old suite are removed. Only then do the live contracts move, bottom-up. Because of this order, `packages/contracts` never imports from a package that depends on it, so there are no cyclic workspace dependencies. Every PR leaves the build, all test suites and `packages/deployment` working.

### Phase 0: preparation

- **0a.** Delete `packages/contracts/task`, `verifydeployed.yml`, and the root `lint:yaml` entry.
- **0b.** Move token-distribution's tests off the `Staking` types and drop its `@graphprotocol/contracts` dependency.
- **0c.** Add a bytecode equivalence check that builds on the existing `scripts/compare-repo-contract-bytecode-excluding-metadata.mjs` and `scripts/bytecode-diff.sh`. It compares bytecode with metadata stripped for:
  - every moved 0.7.6 contract, against a reference committed from the current `packages/contracts` build;
  - the 0.8 contracts whose imports change (HorizonStaking, GraphPayments, PaymentsEscrow, SubgraphService, DisputeManager and their libraries), against the current horizon and subgraph-service builds;
  - the verified source of the mainnet implementations (GraphToken, L1GraphTokenGateway, BridgeEscrow, L1GNS, Curation, L1Staking, StakingExtension), against the on-chain bytecode. This part lives in `legacy` from D2 and ignores metadata and immutable values.

  Every later PR that moves or copies contracts must pass it.

- **0d.** Run `contracts-test` coverage and commit the per-contract line coverage as the parity baseline.

### Phase T: Foundry test ports (parallel)

Each PR:

- creates the destination package skeleton if needed: `package.json`, `foundry.toml` and `test/`. The 0.7.6 Hardhat config (graph-core, graph-token and subgraph-discovery don't use toolshed) comes in Phase 1 with the contracts, since there is nothing to compile before then;
- adds `@graphprotocol/contracts` as a temporary devDependency;
- writes the Foundry tests against its artifacts, following §4;
- deletes the matching TypeScript tests from `contracts-test`.

New packages aren't published yet: they stay `"private": true` until their contracts move in Phase 1.

- **T1.** graph-core. Also proves the 0.8-tests-against-0.7.6-artifacts pattern and the shared proxy/Controller fixture.
- **T2.** graph-token.
- **T3.** subgraph-discovery. Also deletes `gns.test.ts` and `lib/gnsUtils.ts`.
- **T4.** horizon (epochs).
- **T5.** issuance (rewards, with mocks only). This PR may be split by test file group.

The detailed task split is in `phase-t-plan.md`.

### Phase D: removal of dead code

- **D1.** Delete `packages/contracts-test` and the `test` / `test:coverage` scripts in `packages/contracts`. Remove `@graphprotocol/sdk` (catalog and `minumumReleaseAgeExclude`). `build-test.yml` finds coverage files itself, so it needs no change. All live tests have been ported by now.
- **D2.** Create `legacy` from the verified bundles, checked by its `test:self` against mainnet bytecode. Add `legacy/addresses.json` and the `sources.js` entry, and move the audits to `legacy/audits/`.
- **D3.** Delete from `packages/contracts` exactly these contract files, plus their storage contracts where listed:
  - L1GNS, L1GNSStorage, Curation, BancorFormula;
  - Staking, L1Staking, L1StakingStorage, StakingExtension, StakingStorage, Stakes, Exponential, LibFixedMath, L2Staking;
  - DisputeManager, DisputeManagerStorage, ServiceRegistry, ServiceRegistryStorage;
  - AllocationExchange, EthereumDIDRegistry, SubgraphAvailabilityManager.

  Also delete:
  - the unused mocks listed in §2;
  - `addresses-staging.json`, `arbitrum-addresses.json`;
  - `config/`, and `configDir` in `index.js`.

  Live files that also appear in `legacy` bundles stay: Multicall, GNS, GNSStorage, CurationStorage, Managed, GraphUpgradeable, TokenUtils and MathUtils. Nothing that remains imports a deleted file. A PR just before it adds the Ignition alias (§5). L1GNS, Curation, L1Staking, StakingExtension and LibExponential leave the 0c manifest, because `legacy` now checks them.

After D3, `packages/contracts` contains only live contracts.

### Phase 1: moves, bottom-up (one PR each, `git mv` to keep history)

Each PR:

- moves the files;
- switches every consumer's Solidity imports, `deployment` sources and test artifact paths (not the Ignition modules, §5);
- passes 0c;
- removes the moved package's temporary `@graphprotocol/contracts` devDependency;
- flips the moved package to published (drops `"private"`, adds a `publish.yml` option and an initial changeset).

Dependency edges added in each step (removing the devDependency is what prevents a cycle):

| Step | Moves                                   | Edges added                                                                              |
| ---- | --------------------------------------- | ---------------------------------------------------------------------------------------- |
| 1    | graph-core                              | contracts, horizon, subgraph-service, testing, deployment → graph-core                   |
| 2    | graph-token                             | contracts, horizon, subgraph-service, deployment → graph-token. graph-token → graph-core |
| 3    | subgraph-discovery                      | deployment → subgraph-discovery. subgraph-discovery → graph-token, graph-core            |
| 4    | EpochManager into horizon               | horizon → graph-core (already present)                                                   |
| 5    | RewardsManager, MathUtils into issuance | issuance → graph-core. testing, deployment → issuance                                    |

Per-step notes:

1. **graph-core.**
   - Generalizes `deployment`'s artifact loader to one source per package, and adds the new package cases to `tasks/verify-contract.ts`.
   - Switches `packages/testing`'s Solidity imports.
2. **graph-token.**
3. **subgraph-discovery.**
   - Adds GraphCurationToken and SubgraphNFTDescriptor to `horizon/addresses.json`.
   - Changes the L2GraphToken path in `DiscoveryTest.t.sol`. Its tests load L2GraphToken from `PKG_ARTIFACTS`, but L2GraphToken moved to graph-token in step 2, and Foundry does not compile it in subgraph-discovery. Add a `TOKEN_ARTIFACTS` constant pointing at graph-token's artifacts and load it from there with `_deployArtifact`, including its `fs_permissions` entry. This is the one place where Phase 1 changes a test body.
4. **horizon gets EpochManager.**
   - Proves the two-compiler config, the `-v3` alias, the Foundry skip, the lint ignores and the `-v3` CI grep rule.
   - Bumps horizon's OpenZeppelin floor to `^5.4.0`.
5. **issuance gets RewardsManager and MathUtils.**
   - Confirms the Hardhat 3 compile and artifact compatibility (§3, §5).
   - Moves `packages/testing`'s RewardsManager artifact path and `fs_permissions`.
   - Scheduled when no RewardsManager PRs are in flight.

### Phase 2: final removal

- **2a.** Delete the now-empty `packages/contracts` and every remaining reference:
  - `count-patterns.txt` and the `publish.yml` `contracts` option;
  - the docs listed in §5;
  - after checking that the Docker image no longer uses `packages/contracts`.
- **2b.** Run `npm deprecate` on `@graphprotocol/contracts` and `@graphprotocol/sdk`. This is a manual step after 2a.

## Verification

- **Every move or copy PR:**
  - 0c passes.
  - `pnpm build` and `pnpm test` pass across the workspace.
  - `packages/deployment` sync/status against an Arbitrum Sepolia fork reports no code changes.
- **Test-port PRs:**
  - the mapping table is complete;
  - for packages Foundry compiles, coverage is at least the 0d baseline after the move.
- **Final:** a repo-wide search for `@graphprotocol/contracts` returns nothing outside the root `@graphprotocol/contracts-monorepo` name, the Ignition journals, the `@graphprotocol/contracts-7.3.0` alias and its imports, the lockfile and the CHANGELOGs.

## Risks

- **Merge conflicts.** RewardsManager, L2GNS and L2Curation are under active development. Keep T3, T5 and Phase 1 steps 3 and 5 short-lived, and coordinate timing with open work.
- **Ignition modules are frozen.** They stay on the 7.3.0 artifacts. Re-running them, including through `test:integration`, deploys 7.3.0 code, not the moved packages. New deployments go through `packages/deployment`.
- **Two OpenZeppelin versions in horizon and issuance.** Limited to `legacy-0.7/`, and enforced by the CI grep rule. In issuance, Hardhat 3 resolves imports per package, so the import rule in §3 also matters there.
- **Hardhat 3 artifacts consumed by Hardhat 2 tooling.** `packages/deployment` reads the RewardsManager artifact from issuance. Step 5 validates this, with a Hardhat 2-shaped copy as the fallback.
- **Mainnet source drift.** Current source does not reproduce most mainnet implementations. `legacy` therefore archives the verified source, and graph-token's README says its mainnet contracts aren't the deployed code.
- **Test port fidelity.** A rewrite can silently drop behaviours. The mapping table and the coverage baseline guard against this.
- **Library link references.** Only L1Staking (legacy) links a library (`Exponential`). `legacy`'s check covers it. None of the live moved contracts link libraries.
