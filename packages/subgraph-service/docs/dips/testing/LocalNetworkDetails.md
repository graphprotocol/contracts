# Local Network — Details

local-network runs the **full DIPS payer pipeline** (`iisa` + `dipper` + `indexer-service` + `indexer-agent`) locally — useful for development and before the payer services are live on your target network. Bring it up with the `indexing-payments` recipe.

```bash
# in the local-network checkout
just up indexing-payments
```

## Contract Addresses — dynamic

Contracts are redeployed on every `just up`, so addresses change per deploy. Do not hardcode them. Read them from the agent container's mounted config:

```bash
# Horizon contracts (RecurringCollector, PaymentsEscrow, RewardsManager, EpochManager, GraphTallyCollector, L2GraphToken)
docker exec indexer-agent python3 -c \
  "import json; d=json.load(open('/opt/config/horizon.json'))['1337']; print({k:v['address'] for k,v in d.items()})"

# SubgraphService
docker exec indexer-agent python3 -c \
  "import json; print(json.load(open('/opt/config/subgraph-service.json'))['1337']['SubgraphService']['address'])"
```

Chain ID is `1337`.

## Services (indexing-payments recipe)

| Service | Role in DIPS |
| --- | --- |
| chain | EVM hosting Horizon + SubgraphService + RecurringCollector |
| graph-contracts | deploys contracts; writes the address books read above |
| indexer-agent | system under test — accept loop, reconcile, collection |
| indexer-service | validates pushed proposals, queues `pending_rca_proposals` rows |
| dipper | payer side — triggers DIPS origination; the on-chain offer is posted via RAM (`RecurringAgreementManager.offerAgreement`) |
| iisa / iisa-scoring | indexer selection (the dipper calls it to choose indexers) |
| escrow funding service (TBD) | funds the payer's escrow via `RecurringAgreementManager` / issuance, as part of the flow |
| indexing-payments subgraph | indexes `Offer` + `indexingAgreements`; the agent's source of truth |
| graph-node, postgres, ipfs | indexing, agent DB, deployment storage |

## Endpoints (defaults)

| Endpoint | Value |
| --- | --- |
| RPC | `http://localhost:8545` |
| Agent management API | `http://localhost:7600` |
| Network subgraph | `http://localhost:8000/subgraphs/name/graph-network` |
| Indexing-payments subgraph | `http://localhost:8000/subgraphs/name/indexing-payments` |
| Graph-node status | `http://localhost:8030/graphql` |
| Dipper admin RPC | `http://localhost:${DIPPER_ADMIN_RPC_PORT}` |
| Postgres | `localhost:5432` / db `indexer_components_1` |

> Ports and the dipper RPC port come from the resolved `.env`; confirm against your checkout.

## Time control

local-network runs an automine chain — advance time with `cast rpc --rpc-url "$RPC" anvil_mine <blocks> <interval>` (bounded blocks, large intervals) rather than waiting real time. See the time-advancement notes in the plan.

---

- [← Back to DIPS testing](./README.md)
