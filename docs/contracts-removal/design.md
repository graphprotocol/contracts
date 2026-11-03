# Removing `packages/contracts` — Design

Status: draft for review (revision 4: lifecycle rule, ports to 0.8, Ignition and `legacy` simplified)
Date: 2026-11-03

## Goal

Delete `packages/contracts` (`@graphprotocol/contracts`) and `packages/contracts-test` from the monorepo. Every contract that is still in use moves to a package, its unit tests are rewritten in Foundry, and dead code is deleted. Nothing is deployed by this work.

### Lifecycle rule

Where a contract goes depends on whether we expect to change it:

- **Living contracts**, which we expect to upgrade, are ported to Solidity 0.8 and live in their domain package, next to the 0.8 code they work with. The port preserves behaviour and storage layout, and is audited. It ships onchain only with the contract's next real upgrade.
- **Frozen contracts**, which we don't expect to change, move unchanged and must produce identical bytecode, ignoring the metadata hash. They stay 0.7.6 in `graph-core` or `graph-token`. If one ever needs a change, it is ported and moved to its domain package as part of that upgrade.

A contract is living if it has been upgraded since Horizon launched or has planned work. Of the contracts in `packages/contracts`, that is RewardsManager, L2Curation and L2GNS, the three whose implementations changed on Arbitrum One and Arbitrum Sepolia after the Horizon deployment. Everything else is frozen.

No package compiles both 0.7.6 and 0.8 contracts.

Out of scope:

- Porting frozen contracts to Solidity 0.8.
- Any change to contract behaviour. Ports change the language version, not the behaviour.
- Bringing `billing-contracts` into the monorepo. That is a separate sub-project with its own spec.

## Decisions

### 1. npm

- `@graphprotocol/contracts` is frozen at 7.3.0, marked deprecated with `npm deprecate`, and never published again. The git tag `@graphprotocol/contracts@7.3.0` preserves its source, CHANGELOG and docs (`DEPLOYMENT.md`, `TESTING.md`).
- horizon's and subgraph-service's Ignition modules keep only `deploy:protocol`, which builds fresh stacks for local-network and tests. They read live artifacts from the package that owns each contract. The one-off `deploy:migrate` flow, the Ignition deployment records and the suites that depend on them are deleted. The git tag `ignition-records-final`, on the parent commit of Phase 1 step 6, preserves them (§5). The 7.3.0 tag predates the records, so it doesn't.
- `@graphprotocol/sdk` is already deprecated in its README (which points to `@graphprotocol/toolshed`). It also gets `npm deprecate`.
- Known external consumers (graph-network-subgraph, subgraph-studio, network-monitor) pin old versions and are migrated as needed. Addresses come from `@graphprotocol/address-book`, ABIs from `@graphprotocol/interfaces`.

### 2. Package layout

Final dependency graph (arrow = "depends on"):

```
graph-core          → interfaces
graph-token         → graph-core, interfaces
issuance            → graph-core, interfaces
toolshed            → issuance                         (exists today)
horizon             → graph-token, graph-core, issuance, toolshed, interfaces
subgraph-service    → horizon, graph-token, graph-core, toolshed, interfaces
testing             → graph-core, graph-token, horizon, issuance, subgraph-service, interfaces
deployment          → graph-core, graph-token, issuance, horizon, subgraph-service

legacy              (new, private, no workspace dependencies)
```

Edges to `toolshed`, `hardhat-graph-protocol` and `interfaces` that exist today and don't change are omitted.

Rules that keep this acyclic:

- `issuance` depends on `graph-core` and `interfaces` only. Its code and tests never use horizon, subgraph-service or graph-token, because `horizon → toolshed → issuance` already exists.
- The 0.7.6 packages (`graph-core`, `graph-token`) do not use `toolshed` or `hardhat-graph-protocol`. They have their own small Hardhat configs. `legacy` has no Hardhat config.
- `horizon → issuance` is only for deploying RewardsManager from Ignition. It already exists transitively through toolshed.
- `horizon → graph-token` covers TokenUtils and the artifacts its Ignition modules deploy, including GraphCurationToken and SubgraphNFT.
- horizon's Ignition modules also deploy L2GNS and L2Curation, which end up in subgraph-service. horizon can't depend on subgraph-service, so those two modules take their artifacts as inputs, and subgraph-service's `deploy:protocol` passes them in (§5).

| Package            | Contracts                                                                                                                                                                                                                                                                                                | Compiler        |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| `graph-core`       | Controller, Governed, Pausable, Managed, GraphProxy, GraphProxyAdmin, GraphProxyStorage, GraphUpgradeable, EpochManager, EpochManagerStorage                                                                                                                                                             | solc 0.7.6 only |
| `graph-token`      | GraphToken (mainnet), L2GraphToken, GraphTokenUpgradeable, TokenUtils, GraphTokenGateway (base), L1GraphTokenGateway, L2GraphTokenGateway, BridgeEscrow, L1ArbitrumMessenger, L2ArbitrumMessenger, AddressAliasHelper, GraphCurationToken, SubgraphNFT, SubgraphNFTDescriptor, HexStrings, Base58Encoder | solc 0.7.6 only |
| `subgraph-service` | L2GNS, L2GNSStorage, GNS, GNSStorage, L2Curation, CurationStorage, Multicall, ported to 0.8                                                                                                                                                                                                              | solc 0.8 only   |
| `issuance`         | RewardsManager, RewardsManagerStorage, MathUtils, ported to 0.8                                                                                                                                                                                                                                          | solc 0.8 only   |
| `legacy`           | Verified source of the seven mainnet implementations, as plain files (see "legacy package" below)                                                                                                                                                                                                        | none            |

Why the frozen discovery contracts go to `graph-token`:

- GraphCurationToken is an ERC20 and SubgraphNFT is an ERC721, so `graph-token` holds the protocol's token contracts. The NFT helpers (SubgraphNFTDescriptor, HexStrings, Base58Encoder) go with SubgraphNFT.
- `graph-token` already uses OpenZeppelin 3.4.2 under its real name, which both need, and already depends on `graph-core` for Governed.
- The ported contracts reach them only through interfaces (`ISubgraphNFT`, `IGraphCurationToken`) and addresses, never through source.

Deleted, with no replacement:

- Staking: L2Staking. The Arbitrum proxy now runs HorizonStaking.
- AllocationExchange, EthereumDIDRegistry, SubgraphAvailabilityManager.
- The Arbitrum DisputeManager and ServiceRegistry, along with their storage contracts.
- Mocks under `contracts/tests/` that no ported test needs: ArbSysMock, `tests/ens/*`, LegacyGNSMock, MockERC165, MockIssuanceAllocator, MockRewardsEligibilityOracle, MockSubgraphService, and both L1GraphTokenLockTransferTool mocks.
- Each mainnet-only contract is deleted from `packages/contracts` only after its verified source exists in `legacy`.

The test-only `subgraph-discovery` package created in Phase T is deleted in Phase P, when its tests move to subgraph-service.

#### legacy package

- A frozen, private archive of the source that actually runs on mainnet, for GraphToken, L1GraphTokenGateway, BridgeEscrow, L1GNS, Curation, L1Staking and StakingExtension. Mainnet is deprecated: only the GRT contracts are still in use there.
- Current source reproduces only Curation. GraphToken was built with solc 0.7.4, and nine files shared between the implementations, including `Managed.sol`, differ from one implementation to the next. So each contract keeps its own bundle.
- Each bundle is `verified/<Contract>/`: the Sourcify-verified sources, unchanged, with the compiler version and settings. All seven were compiled locally and reproduce mainnet when the package was created. The README links each one to its Etherscan and Sourcify pages, which remain the authority.
- No scripts, no compiler, no tests and no CI job. It has no Solidity imports from the workspace and no Hardhat config. Formatters and linters must not touch `verified/`; the root and package ignore files that D2 added stay.
- `addresses.json` holds every L1 entry (see address-book in §5).
- graph-token keeps its current source for GraphToken, L1GraphTokenGateway and BridgeEscrow, and its README says this is not the code running on mainnet.
- Historical audit reports from `packages/contracts/audits/` (29 PDFs) move to `packages/legacy/audits/`.

### 3. Compiler

Frozen contracts move unchanged, so moving them changes no bytecode. For mainnet-only implementations, the record of what is deployed is `legacy`, not the package that holds the current source. Some frozen contracts can't be upgraded in place and stay 0.7.6 forever:

- GraphToken (mainnet)
- Controller
- GraphProxyAdmin
- SubgraphNFT
- GraphCurationToken (the clone master; `setCurationTokenMaster` can point new pools at a new master, but existing pools keep theirs)

The 0.7.6 settings must reproduce the current build exactly: solc 0.7.6, optimizer enabled, 200 runs, no `evmVersion`, no `viaIR`, default metadata. Everything else follows from that.

#### graph-core and graph-token

- Each has a single Hardhat compiler: 0.7.6 with the settings above.
- graph-token depends on OpenZeppelin `contracts` and `contracts-upgradeable` 3.4.2 under their real names.
- graph-core has no OpenZeppelin imports of its own except EpochManager's SafeMath. It reaches `IERC20` through `IGraphToken`, so it depends on OpenZeppelin `^5.4`, whose `IERC20` uses `>=0.4.16`. That keeps graph-core importable from 0.7.6 code, 0.8 code and 0.8 Foundry tests. EpochManager's SafeMath import is rewritten to the alias `@openzeppelin/contracts-v3` (OpenZeppelin 3.4.2), listed in `dependencies` because graph-core publishes its sources. This combination was verified to produce identical creation and runtime bytecode for EpochManager. The alias is allowed only in graph-core (CI grep check), and its warnings are filtered in graph-core's Hardhat config.
- `packages/deployment` always uses these packages' own 0.7.6 artifacts. That includes GraphProxy, GraphProxyAdmin and Controller, which are deployed from 0.7.6 builds.
- The graph-core files that 0.8 code imports keep the dual pragma `^0.7.6 || ^0.8.27`. Managed has had it since Phase 1 step 1; it was verified to compile under 0.8.35.
- graph-token adds `arbos-precompiles` (needed by L2ArbitrumMessenger).
- `TokenUtils` (in graph-token) also keeps its dual pragma. It is imported as source by 0.8 code in horizon (HorizonStaking, GraphPayments, PaymentsEscrow) and subgraph-service (SubgraphService, DisputeManager, AllocationManager, AllocationHandler), and, after Phase P, by L2Curation and GNS.

#### Ports to 0.8 (Phase P)

- **What changes:** pragma, SafeMath calls replaced by checked arithmetic, OpenZeppelin 3 imports replaced by OpenZeppelin 5 or local equivalents, and whatever 0.8 requires syntactically (`override` specifiers, `type(uint256).max`, explicit conversions). Nothing else.
- **Known port points**, from a trial compile of all three under 0.8:
  - Non-SafeMath arithmetic exists only at `RewardsManager.sol:482` (`+=`), `L2GNS.sol:238` (`+`), `L2GNS.sol:245` (`-`) and `Multicall.sol:23` (`++`). The two L2GNS lines compute the L1-to-L2 subgraph ID alias and rely on wrapping (about 6.7% of IDs would revert under checked arithmetic), so they go in `unchecked`. `test_GetAliasedL2SubgraphID_WrapsAroundMaxUint256` covers it.
  - OpenZeppelin 5 has no `Address.isContract`. `GNS.sol:838` and `L2Curation.sol:469` use `.code.length` instead.
  - `GNS._buildSubgraphID` reads `chainid()`, so it changes from `pure` to `view`. This was the only compile error.
  - The ported contracts are compiled with `viaIR`, unlike the 0.7.6 legacy pipeline. Evaluation order and modifier handling can differ, so the audit covers it explicitly.
- **Storage layout is identical.** `CurationV2Storage` and `GNSV3Storage` inherit OpenZeppelin 3's `Initializable`, whose `_initialized` and `_initializing` sit in ordinary storage slots (slot 16 in L2Curation). OpenZeppelin 5's `Initializable` uses namespaced storage, so it can't be used. The ports keep a local copy with the v3 layout and behaviour under a distinct name, `InitializableV3`, because subgraph-service also compiles OpenZeppelin 5's. RewardsManager has no OpenZeppelin storage. A trial port showed identical layouts slot for slot.
- **Graph-core and graph-token sources stay as they are.** The ported contracts inherit Managed and GraphUpgradeable (dual pragma) and use TokenUtils (dual pragma). All of them, and every interface they reach, compile under 0.8.
- **`interfaces` moves to OpenZeppelin 5 (Pa).** Issuance runs Hardhat 3, which resolves imports per package, so `IGraphToken`'s `IERC20` resolves to `interfaces`' own OpenZeppelin. Today that is 3.4.2 (`<0.8.0`), which a 0.8 RewardsManager can't compile. OpenZeppelin 5's `IERC20` and `IERC165` (`>=0.4.16`) and `IERC721` (`>=0.6.2`) still compile under 0.7.6. Hardhat 2 and Foundry packages resolve OpenZeppelin from their own root and are unaffected.
  - `IGraphCurationToken` stops importing `IERC20Upgradeable`, which OpenZeppelin 5 doesn't have, and extends `IERC20`. Selectors are unchanged, and L2GNS and L2Curation bytecode is identical.
  - It changes the published package: the generated `IERC20Upgradeable` types disappear, the `IERC165` types move to `utils/introspection`, and ABI parameter names change (for example `transfer(recipient, amount)` becomes `transfer(to, value)`, and `setApprovalForAll`'s `_approved` becomes `approved`). That flows into the wagmi ABIs. Pa ships a changeset that says so.
  - OpenZeppelin becomes a regular dependency of `interfaces`, not a devDependency, so published Hardhat 3 consumers can resolve it. `@openzeppelin/contracts-upgradeable` is removed.
- **Revert data changes.** SafeMath reverts with strings; 0.8 reverts with `Panic(0x11)`. Also, `Multicall` re-throws only revert data of at least 68 bytes, so a `Panic` or a short custom error inside a multicall surfaces as empty revert data. Tests that expect the old data are updated, and each Phase P PR lists them.
- **Compiler settings** are the destination package's: 0.8.35 with `viaIR` and `evmVersion: cancun` in subgraph-service, and issuance's 0.8 config. Trial sizes with optimization: RewardsManager 10.6KB, L2GNS 16.9KB, L2Curation 9.6KB, all under the 24KB limit.

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
    - **After a frozen move:** in graph-core and graph-token, Foundry compiles the 0.7.6 sources itself, and tests switch to `deployCode("X.sol:X")` so coverage registers. Each package pins its sources with `compilation_restrictions` and sets the optimizer to 200 runs. Unpinned, Foundry compiles dual-pragma contracts as 0.8.35, so tests would exercise code that isn't deployed. Contracts from another package stay on that package's Hardhat artifacts.
    - **After a port:** the contract is 0.8 source in its package, and tests use it directly.
  - Tests interact through interfaces they can compile under 0.8:
    - In graph-core and in OpenZeppelin-5 packages (horizon, subgraph-service, issuance), they use `@graphprotocol/interfaces`.
    - In graph-token (OpenZeppelin 3.4.2), `IGraphToken`, `ISubgraphNFT` and `IGraphCurationToken` can't be imported from 0.8. Tests there use local minimal interfaces or OpenZeppelin 5's `IERC20` from a test-only remapping.
  - Mocks are 0.8 contracts in the test tree. If a mock needs a 0.7.6 base, it is deployed from an artifact instead.
  - Each package lists its artifact folders explicitly in `foundry.toml` `fs_permissions`, because pnpm symlinks point outside the package.
  - `forge test` depends on Hardhat artifacts, so each package's `test` script builds first. That already holds where `test` runs `pnpm build`.
- **Differential tests for ports.** The suites for ported contracts were written against the 0.7.6 artifacts. After the `git mv`, nothing builds those artifacts any more, and the 7.3.0 npm package is stale (its RewardsManager has no `reclaimRewards`). So each Phase P PR first commits the pre-port Hardhat artifacts of its contracts as test fixtures under `test/fixtures/pre-port/`, with `fs_permissions` entries. The same suite then runs against those fixtures and against the new 0.8 build, and both must pass. Expected differences are limited to revert data, and are listed.
- **Shared fixture.** Upgradeable contracts have an `onlyImpl` `initialize`, so they must sit behind a GraphProxy and be activated through GraphProxyAdmin `upgrade` + `acceptProxyAndCall`. Each package's base test contract has a small helper that:
  - deploys Controller and GraphProxyAdmin from graph-core's artifacts;
  - unpauses the protocol (the Controller constructor leaves it paused);
  - registers mocks with `setContractProxy` and calls `syncAllContracts`;
  - deploys the contract under test behind a proxy.

  Contract-specific setup the ports must reproduce:
  - **L2GNS:** SubgraphNFT (minter and descriptor set), a real L2Curation with a GraphCurationToken master, an L2GraphToken with a minter, and a registered L2 gateway.
  - **L2Curation:** `setSubgraphService` before `collect`.
  - **L2GraphTokenGateway:** `vm.mockCall` / `vm.etch` at ArbSys `0x64`.

- **Unit tests use mocks, not the full network.** A test deploys only the contract under test plus mocks for its dependencies. Issuance tests in particular mock EpochManager, Curation, Staking, GRT and the subgraph service, and never load artifacts from horizon or subgraph-service (see the acyclicity rules in §2). The old rewards tests that went through legacy Staking (restaking, rewards destination, delegation cut) keep their RewardsManager assertions as mock-based unit tests. Their Staking assertions are dropped: that is legacy Staking behaviour, and the Horizon equivalent is already tested in subgraph-service. `packages/testing` stays the home for new cross-package flows.
- **Coverage.** Phase 0d records per-contract **line** coverage from `contracts-test` (solidity-coverage) before anything changes. Branch numbers aren't comparable between solidity-coverage and `forge coverage`, so they're informative only.
  - Every function the baseline hits must still be hit by `forge coverage` once the contract is in its final package: after the move for frozen contracts, after the port for living ones. Line percentages aren't gated, because the two tools count lines differently (Multicall is 6/8 in the baseline and 6/9 in forge with the same 6 hits), so any file below its baseline percentage is listed in the PR with a reason.
  - Frozen contracts whose behaviour is exercised from another package's tests (SubgraphNFT and GraphCurationToken through the L2GNS and L2Curation suites) get direct unit tests in graph-token for any baseline function those suites no longer reach there.

#### Test assignment

| Destination      | Source tests (`contracts-test/tests/unit`)                                                                                                                | Approx. lines |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- |
| issuance         | `rewards/*` except `subgraphAvailability.test.ts`                                                                                                         | 6.8k          |
| subgraph-service | `l2/l2GNS.test.ts`, `l2/l2Curation.test.ts`, `lib/gnsUtils.ts` (written in the test-only `subgraph-discovery` package in T3; moved in Phase P)            | 1.8k          |
| graph-token      | `gateway/*`, `l2/l2GraphToken.test.ts`, `l2/l2GraphTokenGateway.test.ts`, `l2/l2ArbitrumMessengerMock.ts`, `graphToken.test.ts`, `lib/graphTokenTests.ts` | 1.6k          |
| graph-core       | `governance/*`, `upgrade/admin.test.ts`, `epochs.test.ts` (written in horizon in T4; moved in Phase 1 step 4)                                             | 0.7k          |

Notes:

- Today `l2GNS.test.ts` stakes and allocates through L2Staking. Its port uses a staking mock instead.
- `controller.test.ts`, `pausing.test.ts` and `admin.test.ts` use EpochManager, Staking and Curation. Their ports use Managed or GraphUpgradeable mocks instead.
- `l2GraphTokenGateway.test.ts` uses RewardsManager. Its port uses a plain callhook receiver mock.
- `lib/gnsUtils.ts` is also imported by `gns.test.ts`, which is dropped. T3 deletes `gns.test.ts` together with `gnsUtils.ts`.

Dropped, because their contracts are deleted or legacy:

- `gns.test.ts`: it tests L1GNS and is already `describe.skip`.
- `curation/*` (L1 Curation), `disputes/*`, `payments/*`, `serviceRegisty.test.ts`.
- `staking/*`, `l2/l2Staking.test.ts`, `rewards/subgraphAvailability.test.ts`.

#### Mocks needed by ported tests

| Mock                                                                                 | Destination          |
| ------------------------------------------------------------------------------------ | -------------------- |
| GovernedMock, ManagedMock (new, 0.7.6)                                               | graph-core           |
| BridgeMock, InboxMock, OutboxMock, CallhookReceiverMock, TokenUtilsMock (new, 0.7.6) | graph-token          |
| New 0.8 test mocks for the issuance allocator, eligibility oracle and rewards issuer | issuance's test tree |

ManagedMock and TokenUtilsMock are added to `packages/contracts/contracts/tests/` in Phase T, because 0.8 tests can't compile a Managed contract or call the TokenUtils library. They move with their packages in Phase 1. ArbSysMock is not used (ArbSys is faked with `vm.mockCall`), so it stays on the delete list.

Every test-port PR includes a table mapping each old test case to its new Foundry test, or to "dropped" with a reason. Every Phase P PR includes the list of tests whose expected revert data changed.

### 5. Tooling and infrastructure

#### Ignition

Ignition deployed Horizon in 2025. Since then, RewardsManager, L2Curation and L2GNS have been upgraded through `packages/deployment`, so the Ignition deployment records already don't describe what's onchain. Ignition's only remaining job is `deploy:protocol`: building a fresh protocol on a local chain, for local-network (`containers/core/graph-contracts/run.sh`) and tests. `packages/deployment` can't do that today, because it only deploys implementations into existing proxies and new components; replacing Ignition there is out of scope.

- **Deleted:**
  - the `deploy:migrate` tasks, `ignition/modules/migrate/`, the `migrate.*` configs, and the `Migrate*` modules exported from shared module files;
  - the `ServiceRegistry` module, the `LegacyDisputeManager` reference in the `DisputeManager` module, and the `legacyDisputeManagerAddress` and `legacyServiceRegistryAddress` parameters in the protocol configs (local-network writes those address-book stubs itself);
  - `ignition/deployments/` (horizon-arbitrumOne, horizon-arbitrumSepolia, subgraph-service-arbitrumOne, subgraph-service-arbitrumSepolia);
  - `scripts/pre-verify`, `post-verify`, `flatten-verify` and `verify-debug`, which exist only to verify Ignition deployments on live networks;
  - Tenderly's `externalArtifacts` and the `L2Curation` and `RewardsManager` entries in horizon's `verifyList`, and subgraph-service's `tenderly.config.json` if it holds nothing else. `tenderly:upload` itself works from `addresses.json` and stays. If toolshed's Tenderly exports change, toolshed gets a changeset;
  - the integration suites and everything that only serves them: `test/integration`, `scripts/integration`, the `test:integration` task, `addresses-integration-tests.json`, `tasks/test/{seed,ownership}.ts`, and `tasks/transitions/delegation-slashing.ts` (after checking ops don't use it), in both packages. They replay the migration on a fork and depend on data seeded before it;
  - the deployment tests: `test/deployment` and the `test:deployment` scripts in both packages. They load the `migrate.*` configs and are gated on migration steps;
  - the README and `CLAUDE.md` sections for `deploy:migrate`, `test:integration` and `test:deployment`.
- **Kept:** `deploy:protocol` and its modules. Every artifact import reads the live artifact from the package that owns the contract. No npm alias for 7.3.0 is used. A CI job runs `deploy:protocol` on a local Hardhat network, since it's Ignition's only remaining job and local-network depends on it.
- **L2GNS and L2Curation after Phase P.** Their deployment stays in horizon's periphery modules, which already handle ownership: the governor accepts Controller and GraphProxyAdmin at the end of the horizon module, and the periphery wiring runs before that. Only their artifacts change package. horizon can't import subgraph-service's artifacts, so the two modules take the L2GNS and L2Curation artifacts as inputs, and subgraph-service's `deploy:protocol` passes them. The address-book writes don't change, so local-network keeps reading `L2Curation` and `L2GNS` from `horizon.json`. horizon's own `deploy:protocol` task, which deploys without the subgraph service and isn't used by local-network, is deleted in Pc.

#### `packages/deployment`

- The `'contracts'` artifact source is replaced by one source per package: `graph-core`, `graph-token`, `issuance`, `horizon`, `subgraph-service`. This touches:
  - `lib/artifact-loaders.ts`, `lib/contract-registry.ts`, `lib/deploy-implementation.ts`, `lib/deployment-validation.ts`
  - `scripts/generate-abis.ts`, `test/bytecode-comparison.test.ts`
  - `docs/Design.md`, and the `package.json` dependency and `build:clean` script
- `tasks/verify-contract.ts` gets cases for the new packages. Each new package has a Hardhat config with `hardhat-verify`.
- Phase 1 step 1 also added `subgraph-discovery` cases. Step 3 removes them, since no artifact comes from that package any more.
- After Phase P, the RewardsManager, L2Curation and L2GNS registry entries point at their 0.8 artifacts. Their next deployment ships the port, and `sync` against a fork reports them as changed until then.

#### `packages/testing`

- Imports switch to `graph-core`.
- The RewardsManager artifact path moves to issuance in Phase P, along with `foundry.toml` `fs_permissions`.
- The PR checks that `RealRewardsHarness` loads the real RewardsManager. Today it silently falls back to a mock if the artifact is missing.

#### Removed tooling and CI

- `packages/contracts/task` (`@graphprotocol/contracts-task`, the old sdk-based ops tooling) is deleted, not ported. `packages/deployment` replaces it.
- `.github/workflows/verifydeployed.yml` is deleted. It depends on contracts-task.
- `publish.yml` drops `contracts` and adds `graph-core` and `graph-token`.
- The root `lint:yaml` drops `packages/contracts/task/config`.
- `count-patterns.txt` paths are updated.
- `@graphprotocol/sdk` is removed from the `pnpm-workspace.yaml` catalog and from `minumumReleaseAgeExclude` (the key's real, misspelled name).
- `build-test.yml` finds coverage files itself, so it needs no change for the removed packages or the new ones.
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
- L2 entries stay in `horizon/`, where they are today, including L2GNS and L2Curation after they move to subgraph-service. The address book doesn't follow the source package.
- Dropped:
  - Goerli (5) and Arbitrum Goerli (421613);
  - Arbitrum entries for deleted contracts;
  - `arbitrum-addresses.json` (Arbitrum bridge infra, used only by the sdk);
  - `addresses-staging.json` and `addresses-local.json`.

#### Publishing

`graph-core` and `graph-token` follow issuance's package setup:

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

Tests are ported first, against the contracts where they are today. Then dead code and the old suite are removed. Then the frozen contracts move, bottom-up, and the tooling is simplified. Then the living contracts are ported and moved. Last, `packages/contracts` is deleted. Because of this order, `packages/contracts` never imports from a package that depends on it, so there are no cyclic workspace dependencies. Every PR leaves the build, all test suites and `packages/deployment` working.

### Phase 0: preparation

- **0a.** Delete `packages/contracts/task`, `verifydeployed.yml`, and the root `lint:yaml` entry.
- **0b.** Move token-distribution's tests off the `Staking` types and drop its `@graphprotocol/contracts` dependency.
- **0c.** Add a bytecode equivalence check that builds on the existing `scripts/compare-repo-contract-bytecode-excluding-metadata.mjs` and `scripts/bytecode-diff.sh`. It compares bytecode with metadata stripped for:
  - every moved 0.7.6 contract, against a reference committed from the current `packages/contracts` build;
  - the 0.8 contracts whose imports change (HorizonStaking, GraphPayments, PaymentsEscrow, SubgraphService, DisputeManager and their libraries), against the current horizon and subgraph-service builds.

  Every later PR that moves frozen contracts must pass it. Ported contracts leave the check in their Phase P PR, which replaces it with the port checks (Verification).

- **0d.** Run `contracts-test` coverage and commit the per-contract line coverage as the parity baseline.

### Phase T: Foundry test ports (parallel)

Each PR:

- creates the destination package skeleton if needed: `package.json`, `foundry.toml` and `test/`. The 0.7.6 Hardhat config (graph-core and graph-token don't use toolshed) comes in Phase 1 with the contracts, since there is nothing to compile before then;
- adds `@graphprotocol/contracts` as a temporary devDependency;
- writes the Foundry tests against its artifacts, following §4;
- deletes the matching TypeScript tests from `contracts-test`.

New packages aren't published yet: they stay `"private": true` until their contracts move in Phase 1.

- **T1.** graph-core. Also proves the 0.8-tests-against-0.7.6-artifacts pattern and the shared proxy/Controller fixture.
- **T2.** graph-token.
- **T3.** L2GNS and L2Curation, in a test-only `subgraph-discovery` package. Also deletes `gns.test.ts` and `lib/gnsUtils.ts`.
- **T4.** horizon (epochs).
- **T5.** issuance (rewards, with mocks only). This PR may be split by test file group.

The detailed task split is in `phase-t-plan.md`.

### Phase D: removal of dead code

- **D1.** Delete `packages/contracts-test` and the `test` / `test:coverage` scripts in `packages/contracts`. Remove `@graphprotocol/sdk` (catalog and `minumumReleaseAgeExclude`). `build-test.yml` finds coverage files itself, so it needs no change. All live tests have been ported by now.
- **D2.** Create `legacy` from the verified bundles. Add `legacy/addresses.json` and the `sources.js` entry, and move the audits to `legacy/audits/`.
- **D3.** Delete from `packages/contracts` exactly these contract files, plus their storage contracts where listed:
  - L1GNS, L1GNSStorage, Curation, BancorFormula;
  - Staking, L1Staking, L1StakingStorage, StakingExtension, StakingStorage, Stakes, Exponential, LibFixedMath, L2Staking;
  - DisputeManager, DisputeManagerStorage, ServiceRegistry, ServiceRegistryStorage;
  - AllocationExchange, EthereumDIDRegistry, SubgraphAvailabilityManager.

  Also delete:
  - the unused mocks listed in §2;
  - `addresses-staging.json`, `arbitrum-addresses.json`;
  - `config/`, and `configDir` in `index.js`.

  Live files that also appear in `legacy` bundles stay: Multicall, GNS, GNSStorage, CurationStorage, Managed, GraphUpgradeable, TokenUtils and MathUtils. Nothing that remains imports a deleted file. L1GNS, Curation, L1Staking, StakingExtension and LibExponential leave the 0c manifest.

After D3, `packages/contracts` contains only live contracts and the mocks ported tests use.

Phase D landed with two pieces that revision 4 simplifies: D2's `test:self` check against mainnet bytecode, and an npm alias that made Ignition read 7.3.0 artifacts. Phase 1 steps 5 and 6 remove them.

### Phase 1: frozen moves and tooling cleanup (one PR each, `git mv` to keep history)

Each move PR:

- moves the files;
- switches every consumer's Solidity imports, `deployment` sources and test artifact paths;
- passes 0c;
- removes the moved package's temporary `@graphprotocol/contracts` devDependency;
- flips the moved package to published (drops `"private"`, adds a `publish.yml` option and an initial changeset).

| Step | What                                                                                            | Edges added                                                                                                                                              |
| ---- | ----------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1    | graph-core: governance and proxy contracts                                                      | contracts, horizon, subgraph-service, testing, deployment → graph-core. graph-token, subgraph-discovery, issuance → graph-core (test devDependency)      |
| 2    | graph-token: token and bridge contracts                                                         | contracts, horizon, subgraph-service, testing, deployment → graph-token. graph-token → graph-core. subgraph-discovery → graph-token (test devDependency) |
| 3    | graph-token: GraphCurationToken, SubgraphNFT, SubgraphNFTDescriptor, HexStrings, Base58Encoder  | none                                                                                                                                                     |
| 4    | graph-core: EpochManager, EpochManagerStorage                                                   | none                                                                                                                                                     |
| 5    | `legacy`: remove the mainnet bytecode check                                                     | none                                                                                                                                                     |
| 6    | Ignition: delete the migrate flow and verification tooling, read live artifacts, drop the alias | none                                                                                                                                                     |

Per-step notes:

1. **graph-core.**
   - Generalizes `deployment`'s artifact loader to one source per package, and adds the new package cases to `tasks/verify-contract.ts`.
   - Points `CORE_ARTIFACTS` in the Foundry fixtures of graph-token, subgraph-discovery, horizon and issuance at graph-core, with `fs_permissions` entries, because Controller, GraphProxy and GraphProxyAdmin leave `packages/contracts` here while those packages' own contracts don't.
   - Switches `packages/testing`'s Solidity imports.
2. **graph-token.**
   - Adds `testing → graph-token`, because `packages/testing` compiles horizon's sources, which import TokenUtils.
   - Changes the L2GraphToken path in subgraph-discovery's `DiscoveryTest.t.sol` to a `TOKEN_ARTIFACTS` constant pointing at graph-token's artifacts, with its `fs_permissions` entry and a test devDependency.
3. **Frozen discovery contracts into graph-token.**
   - Nothing left in `packages/contracts` imports these files' source. L2GNS and L2Curation use them through interfaces.
   - subgraph-discovery's tests load them from `TOKEN_ARTIFACTS`.
   - Adds GraphCurationToken and SubgraphNFTDescriptor to `horizon/addresses.json`.
   - Adds graph-token unit tests for any baseline function of these files that its own suite doesn't hit (§4 Coverage).
   - Removes the `subgraph-discovery` cases from `packages/deployment`.
   - Keeps the `RewardsHook.t.sol` and `Multicall.t.sol` tests that #1396 added to subgraph-discovery's suite. #1396 itself is closed.
4. **EpochManager into graph-core.**
   - Adds the `@openzeppelin/contracts-v3` alias to graph-core for EpochManager's SafeMath, and a CI grep rule limiting the alias to graph-core.
   - Moves horizon's EpochManager tests (T4) to graph-core, on `deployCode`, so coverage registers.
5. **`legacy` simplified.** Deletes `scripts/`, `mainnet.json`, `targets.json`, the `test:self` script, the solc-js dependency and the CI job. Keeps `verified/`, `addresses.json` and `audits/`, and rewrites the README with Etherscan and Sourcify links for each bundle.
6. **Ignition simplified** as §5 describes. Before the change, tag its parent commit `ignition-records-final`. Every remaining module imports live artifacts: Controller, GraphProxy, GraphProxyAdmin and EpochManager from graph-core; L2GraphToken, L2GraphTokenGateway, GraphCurationToken, SubgraphNFT and SubgraphNFTDescriptor from graph-token; RewardsManager, L2GNS and L2Curation from `@graphprotocol/contracts` until Phase P. Removes the `@graphprotocol/contracts-7.3.0` alias. Adds the `deploy:protocol` CI job.

### Phase P: ports of living contracts to 0.8

Each port PR has two commits: a `git mv` into the destination package, then the port. Reviewers and auditors read the second commit. The first commit doesn't build on its own; the PR says so. Before the first PR, tag the last commit where these contracts are 0.7.6, so the deployed source is one checkout away.

Like the rest of this stack, Phase P PRs reach `main` only after the audit covers their port commits. From then on, `main` holds only audited code, and a hotfix to any of these contracts ships the 0.8 version.

- **Pa. interfaces to OpenZeppelin 5.** Raises `interfaces`' OpenZeppelin to `^5.4` as a regular dependency, removes `contracts-upgradeable`, and changes `IGraphCurationToken` to extend OpenZeppelin 5's `IERC20` (§3). Adds a changeset describing the type and parameter-name changes. Checks that the 0.7.6 builds in graph-core and graph-token, and the bytecode check, are unaffected.
- **Pb. RewardsManager, RewardsManagerStorage and MathUtils into issuance.**
  - Issuance stays 0.8 only.
  - Its T5 suite runs against both builds (§4 Differential tests).
  - Ignition's RewardsManager import and `packages/testing`'s `RM_ARTIFACT` move to issuance's artifacts. The deployment registry entry moves to `issuance`. `RealRewardsHarness` must report 0 skipped.
  - Scheduled when no RewardsManager PRs are in flight.
- **Pc. L2GNS, GNS, L2Curation, their storage contracts and Multicall into subgraph-service.**
  - Adds `InitializableV3`.
  - Moves the T3 suite from `subgraph-discovery` to subgraph-service, runs it against both builds, and deletes the `subgraph-discovery` package.
  - horizon's L2GNS and L2Curation modules take their artifacts as inputs, subgraph-service's `deploy:protocol` passes them, and horizon's own `deploy:protocol` task is deleted (§5).
  - The deployment registry entries move to `subgraph-service`.
  - Scheduled when no L2GNS or L2Curation PRs are in flight.

### Phase 2: final removal

- **2a.** Delete the now-empty `packages/contracts` and every remaining reference:
  - `count-patterns.txt` and the `publish.yml` `contracts` option;
  - the docs listed in §5;
  - after checking that the Docker image no longer uses `packages/contracts`.
- **2b.** Run `npm deprecate` on `@graphprotocol/contracts` and `@graphprotocol/sdk`. This is a manual step after 2a.

## Verification

- **Every frozen move:**
  - 0c passes.
  - `pnpm build` and `pnpm test` pass across the workspace.
  - `packages/deployment` sync against an Arbitrum Sepolia fork reports the same output as the parent commit. Some contracts already differ from what's deployed, so the output is compared rather than required to show no changes. A deployment test loads every registry artifact, because sync can't see a missing one.
- **Every port:**
  - The storage layout of the 0.8 build equals the 0.7.6 build's, slot for slot, compared with `forge inspect <Contract> storageLayout` (Hardhat 2 doesn't emit layouts by default).
  - The ported contract's suite passes against both builds, with only the listed revert-data differences.
  - The 0.8 build fits the 24KB limit.
  - `pnpm build` and `pnpm test` pass across the workspace, and the `deploy:protocol` CI job passes.
  - Fork sync reports only the ported contracts as changed, compared with the parent commit.
- **Test-port PRs:**
  - the mapping table is complete;
  - every function the 0d baseline hits is still hit once the contract is in its final package.
- **Final:** a repo-wide search for `@graphprotocol/contracts` returns nothing outside the root `@graphprotocol/contracts-monorepo` name, the lockfile, the CHANGELOGs, this design folder, the test-mapping tables and `packages/legacy/verified`.

## Risks

- **Merge conflicts.** RewardsManager, L2GNS and L2Curation are under active development. Keep Phase P PRs short-lived, and coordinate timing with open work.
- **A port changes behaviour.** Mitigated by the storage-layout check, differential tests against the 0.7.6 build, and the audit of the port commit. `InitializableV3`, the L2GNS alias arithmetic and the switch to `viaIR` are the most sensitive pieces.
- **Repo source differs from what's deployed for ported contracts until their next upgrade.** The pre-port git tag and Sourcify hold the deployed source. A hotfix ships the audited 0.8 version.
- **OpenZeppelin 5 in `interfaces`.** Hardhat 3 consumers resolve `interfaces`' imports with its own OpenZeppelin, and the published types and ABI parameter names change. Pa checks that every package still builds with identical frozen bytecode, and its changeset tells external consumers.
- **Mainnet source drift.** Current source does not reproduce most mainnet implementations. `legacy` therefore archives the verified source, and graph-token's README says its mainnet contracts aren't the deployed code.
- **Test port fidelity.** A rewrite can silently drop behaviours. The mapping table and the coverage baseline guard against this.
- **Library link references.** None of the live moved contracts link libraries.
