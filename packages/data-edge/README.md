# Data Edge

A DataEdge contract stores arbitrary data on-chain on any EVM compatible blockchain. It does not execute anything: it exists so that off-chain consumers — typically a subgraph — can read the calldata sent to the contract, decode it, and update their own state accordingly.

Posting a payload is a plain transaction to the contract. The fallback function accepts any calldata and never reverts, so there is no ABI to conform to and no permissioning: **it is up to the implementer to define the calldata format and how to decode it.**

## Contracts

| Contract                                             | Behaviour                                                                                                     |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| [`DataEdge`](contracts/DataEdge.sol)                 | Fallback is a no-op. The payload lives only in the transaction calldata, so consumers must read transactions. |
| [`EventfulDataEdge`](contracts/EventfulDataEdge.sol) | Fallback emits `Log(bytes data)` with the full calldata. Costs more gas, but consumers can index events only. |

`EventfulDataEdge` is the one to pick unless you have a specific reason not to: subgraphs (and most indexing tooling) handle events far more comfortably than raw calldata, and some L2 RPCs make calldata retrieval awkward.

### Payload convention

The contracts impose no format, but the convention used across The Graph is the standard Solidity one, so tooling can treat a payload like a normal function call:

```
<4-byte selector of someMethodName(bytes)> || <abi.encode(payload)>
```

Consumers switch on the selector to decide how to decode the rest. See `test/dataedge.test.ts` for a worked example.

### Considerations

- **The fallback is `payable`.** Neither contract has a withdrawal path, so any ETH sent to a DataEdge is permanently locked. Send value only if you intend to burn it.
- **Anyone can post.** There is no access control. A consumer must filter by sender (or otherwise authenticate the payload) if it cares about provenance. This is why deployments are per-use-case rather than shared — see the naming below.
- **Nothing is validated on-chain.** Malformed payloads are accepted and cost gas like any other; correctness is entirely a consumer-side concern.

## Deployments

Deployed addresses live in [`addresses.json`](addresses.json), keyed by chain ID. That file is the source of truth and is updated by the deploy task — it is not duplicated here.

Each deployment serves a single use case and is named for it, because the contract accepts posts from anyone: a shared instance would force every consumer to filter other payloads out of its event stream. Keys are `<use-case><contract>`, e.g. `EBOEventfulDataEdge`.

| Prefix | Use case                     |
| ------ | ---------------------------- |
| `EBO`  | Epoch Block Oracle           |
| `SAO`  | Subgraph Availability Oracle |
| `REO`  | Rewards Eligibility Oracle   |

Adding a use case means adding a prefix to the `DeployName` enum in [`tasks/deploy.ts`](tasks/deploy.ts); the task rejects anything not listed there.

## Development

### Setup

```bash
pnpm install
cp .env.sample .env   # then fill in the values you need
```

`.env` keys: `MNEMONIC` (deployer), `INFURA_KEY` (RPC for mainnet and sepolia; the Arbitrum networks use public endpoints), `ETHERSCAN_API_KEY` and `ARBISCAN_API_KEY` (verification). `ACCOUNT_INDEX` optionally selects a derivation index other than 0.

### Common commands

```bash
pnpm build           # compile contracts and generate TypeChain types into build/
pnpm test            # build, then run the Hardhat test suite
pnpm test:gas        # same, with a gas report written to reports/gas-report.log
pnpm test:coverage   # solidity-coverage
pnpm lint            # solhint + eslint + prettier + markdownlint
pnpm size            # contract bytecode sizes
pnpm security        # slither (requires slither-analyzer, installed by the script)
```

Supported networks are declared in [`hardhat.config.ts`](hardhat.config.ts): `mainnet`, `sepolia`, `arbitrum-one` and `arbitrum-sepolia`, plus the local `hardhat` and `ganache` networks.

### Deploying

Deployment is a Hardhat task. `--contract` takes `DataEdge` or `EventfulDataEdge`; `--deploy-name` takes one of the use-case prefixes above and becomes the prefix of the key written back to `addresses.json`.

```bash
npx hardhat data-edge:deploy \
  --contract EventfulDataEdge \
  --deploy-name EBO \
  --network arbitrum-sepolia
```

There is a `deploy` script that wraps the same task, but invoke it as `pnpm run deploy -- --contract ...` — bare `pnpm deploy` is pnpm's own built-in command and will not run the script.

On success the task appends `<deploy-name><contract>` (for example `EBOEventfulDataEdge`) to `addresses.json` under the network's chain ID — commit that change.

Verify afterwards with:

```bash
npx hardhat verify --network arbitrum-sepolia <address>
```

### Posting data

Two tasks help build and submit payloads by hand:

```bash
# Encode <selector(bytes)> || abi.encode(data) and print the resulting calldata
npx hardhat data:craft \
  --edge <edge-address> \
  --selector setEpochBlocksPayload \
  --data 0xdeadbeef \
  --network arbitrum-sepolia

# Send raw calldata to the edge contract
npx hardhat data:post \
  --edge <edge-address> \
  --data <calldata-from-data:craft> \
  --network arbitrum-sepolia
```

## Copyright

Copyright &copy; 2022 The Graph Foundation

Licensed under [GPL license](LICENSE).
