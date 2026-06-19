# DIPS Local-Network Test Plan

> **Status: Full-pipeline (developer)** — Exercises every DIPS behavior end-to-end on **local-network**, driving all services including the payer side (`iisa`/`dipper`). It uses local-only mechanics — proposal origination via the dipper admin RPC, agent-boundary proposal injection for the negative checks, and chain time-travel (`anvil_mine`). For the indexer-facing runbook that an indexer follows on testnet, see [TestnetIndexerGuide](./TestnetIndexerGuide.md).
>
> **Navigation**: [← Back to DIPS testing](./README.md) | [TestnetIndexerGuide](./TestnetIndexerGuide.md) | [LocalNetworkDetails](./LocalNetworkDetails.md)

Run a full DIPS environment on local-network and verify, end-to-end, that every documented DIPS behavior works. The payer side (`iisa`/`dipper`) proposes agreements and triggers the on-chain offer via RAM (`RecurringAgreementManager`); `indexer-service` validates and queues them; `indexer-agent` accepts, allocates, and collects. The plan drives the real services through the whole chain. The goal is happy-path regression confidence — prove documented behaviors work; adversarial/error modes are a separate optional set of negative checks.

## Addresses & RPC

Local-network redeploys contracts on every `just up`, so addresses are dynamic. Read them from the agent container and export the shell variables the commands use — see [LocalNetworkDetails](./LocalNetworkDetails.md) for the exact `/opt/config` read commands.

| Parameter | Value |
| --- | --- |
| RPC | `http://localhost:8545` |
| Chain ID | `1337` |

Commands use shell variables (`$RPC`, `$SUBGRAPH_SERVICE`, `$RECURRING_COLLECTOR`, `$RECURRING_AGREEMENT_MANAGER`, `$PAYMENTS_ESCROW`, `$REWARDS_MANAGER`, `$EPOCH_MANAGER`) populated from your local deploy.

---

## Background

### What DIPS does

A payer pays an indexer to keep a deployment indexed under an on-chain Recurring Collection Agreement (RCA). The indexer-agent accepts the agreement on-chain, keeps the deployment allocated, and collects payment periodically through `SubgraphService` + `RecurringCollector`. Collection happens in place: the agent keeps the backing allocation open and collects against it across successive windows.

### Key Invariants

- **The offer is posted via RAM.** The dipper triggers `RecurringAgreementManager.offerAgreement(...)`; RAM posts the offer on-chain, so the agreement's on-chain `payer` is the RAM contract address. Separately, the indexer-agent does the on-chain `acceptIndexingAgreement`.
- **IISA selects the indexer.** The payer supplies only the deployment, chain, and candidate count; it cannot target a specific indexer.
- **Per-collection payout = min(data-service request, RCA payer cap).** Request = `collectionSeconds × (tokensPerSecond + tokensPerEntityPerSecond × entities)`. Cap = `maxOngoingTokensPerSecond × collectionSeconds` (plus `maxInitialTokens` on the first collection only).
- **`collectionSeconds` is capped at `maxSecondsPerCollection`.** Elapsed time beyond the cap is forfeited, not errored.
- **DIPS allocations are long-lived.** The agent keeps them open and collects in place; `unallocate` is blocked without `--force`; a force-close cancels the agreement on-chain.
- **Deterministic collection errors throttle retries**, they do not cancel.
- **The rule reaper is skipped** when the indexing-payments subgraph lags chain head by more than 5 minutes.

---

## Prerequisites

Confirm each item before Cycle D-1.

> 💡 Addresses come from the deployed address books. Local-network exposes them in the agent container at `/opt/config/horizon.json` and `/opt/config/subgraph-service.json`; a testnet uses the published address book. The commands below use shell variables for those values: contract addresses (`$RPC`, `$SUBGRAPH_SERVICE`, `$RECURRING_COLLECTOR`, `$RECURRING_AGREEMENT_MANAGER`, `$PAYMENTS_ESCROW`, `$REWARDS_MANAGER`, `$EPOCH_MANAGER`), accounts (`$PAYER`, `$INDEXER`), keys (`$PAYER_SECRET`, `$ORACLE_SECRET`), endpoints (`$AGENT_URL`, `$NETWORK_SUBGRAPH_URL`, `$INDEXING_PAYMENTS_SUBGRAPH_URL`, `$DIPPER_ADMIN_RPC_PORT`), and Postgres (`$PG_HOST`, `$PG_PORT`).

- [ ] All DIPS services running and healthy: chain, graph-contracts (contracts deployed, address books present), graph-node, ipfs, postgres, indexer-agent, indexer-service, tap-agent, dipper, iisa/iisa-scoring, and the supporting stack (gateway, redpanda, oracles).
- [ ] Agent started with DIPS enabled (`--enable-dips true`) and an indexing-payments subgraph endpoint or deployment configured.

  Agent healthy:

  ```bash
  curl -s "$AGENT_URL" -H 'content-type: application/json' \
    -d '{"query":"{ indexingRules(merged:false){ identifier } }"}' | jq -e '.data'
  ```

- [ ] Indexer provisioned in `SubgraphService` (active provision).
- [ ] Network subgraph and indexing-payments subgraph synced to chain head.

  Subgraph synced — compare the subgraph `_meta` block to chain head. Example for the network subgraph; check the indexing-payments subgraph the same way against `$INDEXING_PAYMENTS_SUBGRAPH_URL`:

  ```bash
  curl -s "$NETWORK_SUBGRAPH_URL" -H 'content-type: application/json' \
    -d '{"query":"{ _meta { block { number } } }"}' | jq -r '.data._meta.block.number'
  ```

- [ ] At least one indexable subgraph deployment available, and one rewards-denied deployment available (for the sizing variant).

> 💡 Account and payer-escrow funding are handled automatically by local-network components as part of the DIPS flow (a service that funds the payer's escrow via `RecurringAgreementManager` / issuance).

### Roles Needed

| Role                            | Needed for                                                          | Holder                                |
| ------------------------------- | ------------------------------------------------------------------- | ------------------------------------- |
| Payer / gateway operator | triggers DIPS origination via the dipper; the agreement's on-chain `payer` is the RAM contract | payer-side, operated externally |
| Indexer operator                | runs the agent; provisioned in SubgraphService                      | the indexer                           |
| Subgraph availability oracle    | `RewardsManager.setDenied` (sizing + N-6)                           | SAO key                               |
| Governor                        | one-time `setSubgraphAvailabilityOracle`                            | council/governor                      |

---

## Observation toolbox

Canonical read commands, defined here and referenced throughout. Replace `<HASH>`, `<ALLOC_ID>`, `<AGREEMENT_ID>`, `<DEADLINE>`, `<NONCE>` with the values for the run.

Indexing rules — agent management API:

```bash
curl -s "$AGENT_URL" -H 'content-type: application/json' \
  -d '{"query":"{ indexingRules(merged:false){ identifier decisionBasis } }"}'
```

Active allocation for a deployment — network subgraph:

```bash
curl -s "$NETWORK_SUBGRAPH_URL" -H 'content-type: application/json' \
  -d '{"query":"{ allocations(where:{ subgraphDeployment_:{ipfsHash:\"<HASH>\"}, status:Active }, orderBy:createdAt, orderDirection:desc, first:1){ id } }"}'
```

Offer indexed — indexing-payments subgraph (`id` = the bytes16 agreement id):

```bash
curl -s "$INDEXING_PAYMENTS_SUBGRAPH_URL" -H 'content-type: application/json' \
  -d '{"query":"{ offer(id:\"<AGREEMENT_ID>\"){ offerHash } }"}'
```

Agreement — indexing-payments subgraph:

```bash
curl -s "$INDEXING_PAYMENTS_SUBGRAPH_URL" -H 'content-type: application/json' \
  -d '{"query":"{ indexingAgreements(where:{ allocationId:\"<ALLOC_ID>\", state_in:[1,3] }){ id state lastCollectionAt } }"}'
```

On-chain agreement state + `lastCollectionAt` — `RecurringCollector.getAgreement`. `state` is the last field (enum `NotAccepted=0` / `Accepted=1` / `CanceledByServiceProvider=2` / `CanceledByPayer=3`); `lastCollectionAt` is the 5th field:

```bash
cast call --rpc-url "$RPC" "$RECURRING_COLLECTOR" \
  "getAgreement(bytes16)(address,uint64,uint32,address,uint64,uint32,address,uint64,uint32,uint256,uint256,bytes32,uint64,uint16,uint8)" \
  "<AGREEMENT_ID>"
```

On-chain collectability — `RecurringCollector.getCollectionInfo` → `(collectable, collectionSeconds, reason)`:

```bash
cast call --rpc-url "$RPC" "$RECURRING_COLLECTOR" \
  "getCollectionInfo(bytes16)(bool,uint256,uint8)" "<AGREEMENT_ID>"
```

Allocation tokens — `SubgraphService.getAllocation` (`tokens` is the 3rd field):

```bash
cast call --rpc-url "$RPC" "$SUBGRAPH_SERVICE" \
  "getAllocation(address)((address,bytes32,uint256,uint256,uint256,uint256,uint256,uint256))" "<ALLOC_ID>"
```

Derive the agreement id — `RecurringCollector.generateAgreementId` from payer (the RAM contract, `$RECURRING_AGREEMENT_MANAGER`), dataService (`$SUBGRAPH_SERVICE`), serviceProvider (`$INDEXER`), deadline, nonce:

```bash
cast call --rpc-url "$RPC" "$RECURRING_COLLECTOR" \
  "generateAgreementId(address,address,address,uint64,uint256)(bytes16)" \
  "$RECURRING_AGREEMENT_MANAGER" "$SUBGRAPH_SERVICE" "$INDEXER" "<DEADLINE>" "<NONCE>"
```

Pending proposal row — indexer DB (observe that indexer-service queued a proposal):

```bash
psql -h "$PG_HOST" -p "$PG_PORT" -U postgres -d indexer_components_1 -tAq \
  -c "SELECT id, status FROM pending_rca_proposals ORDER BY created_at DESC LIMIT 5;"
```

Payer escrow balance — `PaymentsEscrow.getBalance(payer, recurringCollector, indexer)` (read-only; funding itself is automatic — see Prerequisites):

```bash
cast call --rpc-url "$RPC" "$PAYMENTS_ESCROW" \
  "getBalance(address,address,address)(uint256)" \
  "$PAYER" "$RECURRING_COLLECTOR" "$INDEXER"
```

---

## Conventions

Each test is written as:

- **Objective** — one line.
- **Prerequisites** — what must be true (usually "previous test/cycle complete"), when relevant.
- **Steps** — network-agnostic instruction (e.g. "Have the payer propose an agreement for deployment X") plus a concrete reference snippet, labeled, with environment-specific bits flagged.
- **Verification** — observable signals, when an extra read clarifies the outcome.
- **Pass Criteria** — checkboxes, each tied to an observable signal and expected value.

Two environment-note patterns recur:

- **Time advancement.** Local-network mines/fast-forwards (e.g. `cast rpc anvil_mine <blocks> <interval>`); a testnet waits real elapsed time. Tests state durations abstractly (e.g. "wait until `minSecondsPerCollection` has elapsed").
- **Payer control.** Actions assume you can drive the payer side (`iisa`/`dipper`). Where you don't control the payer, the note states what to arrange instead.

---

## Test Sequence Overview

| Cycle | Area                              | Tests       | Notes                                                          |
| ----- | --------------------------------- | ----------- | -------------------------------------------------------------- |
| D-1   | Environment readiness             | D-1.1 - D-1.2 | Run prerequisites, capture baseline; no prior state needed     |
| D-2   | Proposal origination (payer side) | D-2.1 - D-2.3 | Payer control; IISA selects indexer                            |
| D-3   | Agent acceptance                  | D-3.1 - D-3.2 | Two paths: reuse allocation vs new allocation via multicall    |
| D-4   | Allocation sizing                 | D-4.1 - D-4.2 | Reward-earning vs rewards-denied; SAO needed for the variant   |
| D-5   | Indexing & rule reconciliation    | D-5.1 - D-5.3 | Steady state; wait ≥2 reconcile cycles                         |
| D-6   | Recurring collection              | D-6.1 - D-6.5 | Drive 2-3 windows; advance time per env                        |
| D-7   | Long-lived allocation protection  | D-7.1 - D-7.3 | `--force` is destructive — run D-7.3 last                      |
| D-8   | Cancellation                      | D-8.1 - D-8.3 | Re-create a fresh agreement; mind the ~15-min cooldown         |
| E     | Edge cases                        | E-1 - E-4   | Off-the-main-line, not failures; optional                      |
| N     | Negative checks                   | N-1 - N-7   | Injection-driven fault scenarios; optional                     |

---

## Cycle D-1 — Environment readiness

### D-1.1 Prerequisites green

**Objective**: Confirm the world is sane before testing.

**Steps**: Run the [Prerequisites](#prerequisites) readiness checklist top to bottom.

**Pass Criteria**:

- [ ] Every Prerequisites checklist item is green (all DIPS services healthy; agent up with `--enable-dips true` and an indexing-payments subgraph configured; provision active; both subgraphs synced to chain head).

---

### D-1.2 Baseline capture

**Objective**: Capture a baseline — pick the target reward-earning deployment and identify the rewards-denied deployment for the D-4 sizing variant.

**Prerequisites**: D-1.1 green.

**Steps**: List deployment indexing rules and pick a target reward-earning deployment (one with an `always` rule); identify a separate rewards-denied deployment for the D-4 sizing variant. Record both IPFS hashes for downstream tests.

Baseline rules — Observation toolbox "Indexing rules", reading the identifiers so you can pick a target:

```bash
curl -s "$AGENT_URL" -H 'content-type: application/json' \
  -d '{"query":"{ indexingRules(merged:false){ identifier identifierType decisionBasis allocationAmount } }"}' \
  | jq -r '.data.indexingRules[] | select(.identifierType=="deployment") | "\(.identifier)\t\(.decisionBasis)"'
```

Pick a deployment whose `decisionBasis` is `always` (reward-earning target) and export it as `<HASH>` for later tests. The `identifier` is the IPFS hash to use downstream.

> 💡 The rewards-denied deployment is the one flagged in the last prerequisite ("one rewards-denied deployment available"). Confirm it on-chain with `RewardsManager.isDenied(bytes32)` (returns `true`) and record its hash separately; it is only used in D-4.
>
> ```bash
> cast call --rpc-url "$RPC" "$REWARDS_MANAGER" "isDenied(bytes32)(bool)" "<DEPLOYMENT_BYTES32>"
> ```

**Pass Criteria**:

- [ ] A target reward-earning deployment hash is chosen and recorded — it has an `always` rule in the toolbox "Indexing rules" output.
- [ ] A rewards-denied deployment is identified and its hash recorded — reserved for the D-4 sizing variant.

---

## Cycle D-2 — Proposal origination (payer side)

### D-2.1 Trigger origination (inject the indexing-requirement signal)

**Objective**: Inject the indexing-requirement signal that drives the dipper to originate the agreement.

**Prerequisites**: D-1 complete. The dipper and IISA are running; IISA can select the target indexer for the deployment.

**Steps**: Produce an indexing-requirement message to the `indexing-requirements` Redpanda topic; the dipper's signal consumer reads it, runs IISA selection, and offers the agreement. Redpanda auto-create is off, so create the topic first if it doesn't exist.

```bash
# create the topic if absent (idempotent)
docker exec redpanda rpk topic create indexing-requirements --brokers redpanda:9092 2>/dev/null || true

# produce the signal for the target deployment
echo '{"subgraph_deployment_id":"<HASH>","redundancy_factor":1,"chain_id":1337,"version":1}' \
  | docker exec -i redpanda rpk topic produce indexing-requirements --brokers redpanda:9092
```

Message schema: `{ subgraph_deployment_id, redundancy_factor, chain_id, version }`.

**Pass Criteria**:

- [ ] The dipper consumes the signal and begins origination — it records an agreement for the deployment (verified in D-2.2).

---

### D-2.2 Pending proposal queued + dipper agreement `CREATED`

**Objective**: Confirm the service-level gRPC accept queued a pending proposal and the dipper recorded the agreement.

**Prerequisites**: D-2.1 issued. The dipper PUSHES the proposal to the selected indexer-service via `SubmitAgreementProposal`; the indexer-service validates it (deployment indexable, deadline not passed, meets minimum price) and, on accept, queues a `pending_rca_proposals` row (status `pending`) and responds Accept. This service-level accept is not the on-chain accept.

**Steps**: Read the dipper agreement record and the pending proposal row.

**Pass Criteria**:

- [ ] The dipper shows an agreement for the deployment with status `CREATED` — read-only admin RPC `get_agreements_by_deployment_id` (filter by `<HASH>`). Use the returned record's `deadline`/`nonce` to derive the agreement id.
- [ ] A `pending_rca_proposals` row exists with status `pending` — Observation toolbox "Pending proposal row" (the service-level accept queued it):

  ```bash
  psql -h "$PG_HOST" -p "$PG_PORT" -U postgres -d indexer_components_1 -tAq \
    -c "SELECT id, status FROM pending_rca_proposals WHERE status='pending' ORDER BY created_at DESC LIMIT 5;"
  ```

---

### D-2.3 On-chain offer indexed on subgraph

**Objective**: Confirm the on-chain offer was posted — the dipper triggers `RecurringAgreementManager.offerAgreement`, RAM posts it — and it indexed on the indexing-payments subgraph (the end state of proposal origination).

**Prerequisites**: D-2.2 complete. After the indexer-service Accept, the dipper triggers `RecurringAgreementManager.offerAgreement(collector, OFFER_TYPE_NEW=1, abi.encode(rca))`; RAM posts the offer on `RecurringCollector`, emitting `OfferStored`, with the RAM contract as the agreement `payer`. The `Offer` entity then appears on the indexing-payments subgraph.

**Steps**: Derive the agreement id, then query the `Offer` entity.

Derive the agreement id — once `deadline`/`nonce` are known (read them from the agreement record), the Observation toolbox "Derive the agreement id" (`generateAgreementId`) gives the concrete id for the offer query. The `payer` is the RAM contract (`$RECURRING_AGREEMENT_MANAGER`):

```bash
cast call --rpc-url "$RPC" "$RECURRING_COLLECTOR" \
  "generateAgreementId(address,address,address,uint64,uint256)(bytes16)" \
  "$RECURRING_AGREEMENT_MANAGER" "$SUBGRAPH_SERVICE" "$INDEXER" "<DEADLINE>" "<NONCE>"
```

> ⚠️ The agreement id is derived from (payer=RAM contract, dataService=SubgraphService, serviceProvider=indexer, deadline, nonce). Read the id from the agreement record, or derive it only once deadline and nonce are known — do not assume it.

**Pass Criteria**:

- [ ] The `Offer` entity is present on the indexing-payments subgraph — Observation toolbox "Offer indexed", using the derived `<AGREEMENT_ID>`. Presence confirms the offer was posted via RAM:

  ```bash
  curl -s "$INDEXING_PAYMENTS_SUBGRAPH_URL" -H 'content-type: application/json' \
    -d '{"query":"{ offer(id:\"<AGREEMENT_ID>\"){ offerHash } }"}' | jq -e '.data.offer'
  ```

---

## Cycle D-3 — Agent acceptance

The agent's acceptance loop runs every `--dips-acceptance-interval` (default 5s). Each pass runs an offer pre-flight (confirms the `Offer` is present on the subgraph) and then calls `SubgraphService.acceptIndexingAgreement`. Two variants depend on whether an active allocation already exists for the deployment.

> ⚠️ **Time advancement.** On local-network the accept tx confirms only once a follow-up block is mined — mine one so the agent's `waitForTransaction` resolves: `cast rpc --rpc-url "$RPC" evm_mine`. On a testnet, blocks arrive on their own.

> 💡 D-3.1 and D-3.2 differ only in whether an allocation pre-exists. Verify which path ran by checking whether a new allocation id appeared (D-3.2) versus the prior one being reused (D-3.1) in the toolbox "Active allocation" output.

### D-3.1 Accept reusing an existing allocation

**Objective**: The indexer-agent accepts the agreement on-chain against an already-active allocation with a single `acceptIndexingAgreement` tx.

**Prerequisites**: D-2 complete (the `Offer` entity is present and the `pending_rca_proposals` row is `pending`). An active allocation already exists for the deployment — have one open before D-2 to exercise this path.

**Steps**: Let the acceptance loop run. The agent accepts against the existing allocation with a single `acceptIndexingAgreement` tx.

**Pass Criteria**:

- [ ] The `pending_rca_proposals` row flips to `accepted` — Observation toolbox "Pending proposal row", look for status `accepted`.
- [ ] A `dips` indexing rule exists for the deployment — Observation toolbox "Indexing rules", `decisionBasis == "dips"` and `identifier == <HASH>`.
- [ ] An active allocation exists for the deployment and the prior allocation id is reused — Observation toolbox "Active allocation".
- [ ] On-chain agreement state is `Accepted` (=1) — Observation toolbox "On-chain agreement state" (`getAgreement`), last field is `1`.
- [ ] The dipper agreement status is `ACCEPTED_ON_CHAIN` — read-only admin RPC `get_agreements_by_deployment_id` (filter by `<HASH>`).

---

### D-3.2 Accept opening a new allocation via multicall

**Objective**: With no allocation present, the agent opens one atomically via `multicall(startService, acceptIndexingAgreement)`.

**Prerequisites**: D-2 complete. No active allocation exists for the deployment — close any existing one first to force this path.

**Steps**: Ensure no active allocation exists, then let the acceptance loop run. The agent opens an allocation atomically via `multicall(startService, acceptIndexingAgreement)`.

Close an existing allocation to force D-3.2 — indexer-cli. Horizon allocations need a POI and the epoch start block; use a zero POI with `--force`. The epoch start block comes from `EpochManager.currentEpochBlock()`:

```bash
EPOCH_BLOCK=$(cast call --rpc-url "$RPC" "$EPOCH_MANAGER" 'currentEpochBlock()(uint256)')
ZERO_POI=0x0000000000000000000000000000000000000000000000000000000000000000
graph indexer allocations close <ALLOC_ID> "$ZERO_POI" "$EPOCH_BLOCK" --force --network <NETWORK>
```

**Pass Criteria**:

- [ ] The `pending_rca_proposals` row flips to `accepted` — Observation toolbox "Pending proposal row", look for status `accepted`.
- [ ] A `dips` indexing rule exists for the deployment — Observation toolbox "Indexing rules", `decisionBasis == "dips"` and `identifier == <HASH>`.
- [ ] A new active allocation id appeared for the deployment — Observation toolbox "Active allocation".
- [ ] On-chain agreement state is `Accepted` (=1) — Observation toolbox "On-chain agreement state" (`getAgreement`), last field is `1`.
- [ ] The dipper agreement status is `ACCEPTED_ON_CHAIN` — read-only admin RPC `get_agreements_by_deployment_id` (filter by `<HASH>`).

---

## Cycle D-4 — Allocation sizing

The agent sizes the DIPS allocation by whether the deployment earns indexing rewards. Run on two deployments: the reward-earning target and the rewards-denied one from D-1.

> ⚠️ Denying requires the subgraph availability oracle to be configured — a one-time governor setup, `RewardsManager.setSubgraphAvailabilityOracle`. Without it, `setDenied` cannot be sent from the oracle key and the denied-variant check can't run. Always undeny afterward.

### D-4.1 Reward-earning sizing

**Objective**: A reward-earning deployment's allocation uses the deployment's indexing-rule `allocationAmount`, or `defaultAllocationAmount` if the rule has none.

**Prerequisites**: D-3 mechanics understood; accepted agreement on the reward-earning target.

**Steps**: Read allocation tokens — Observation toolbox "Allocation tokens" (`getAllocation`), `tokens` is the 3rd field.

**Pass Criteria**:

- [ ] The allocation `tokens` equals the rule's `allocationAmount` (or `defaultAllocationAmount` when the rule sets none) — name the source, not a number.

---

### D-4.2 Rewards-denied sizing

**Objective**: A rewards-denied deployment's allocation uses `--dips-allocation-amount` (env `INDEXER_AGENT_DIPS_ALLOCATION_AMOUNT`), default `0`. A zero-token allocation is valid for DIPS — collection pays the RCA amount, independent of allocation size.

**Prerequisites**: The rewards-denied deployment from D-1. Subgraph availability oracle configured.

**Steps**: Deny the deployment with `RewardsManager.setDenied(bytes32,bool)` from the oracle key, accept and size the allocation, then undeny afterward to keep the run idempotent.

Deny / undeny — sent from the oracle key:

```bash
cast send --rpc-url "$RPC" --private-key "$ORACLE_SECRET" \
  "$REWARDS_MANAGER" "setDenied(bytes32,bool)" "<DEPLOYMENT_BYTES32>" true
# undeny: same call with false
```

Confirm denial:

```bash
cast call --rpc-url "$RPC" "$REWARDS_MANAGER" "isDenied(bytes32)(bool)" "<DEPLOYMENT_BYTES32>"
# → true
```

Read allocation tokens — Observation toolbox "Allocation tokens" (`getAllocation`), `tokens` is the 3rd field.

**Pass Criteria**:

- [ ] The allocation `tokens` equals `--dips-allocation-amount` (default `0` → a valid zero-token allocation).

---

## Cycle D-5 — Indexing & rule reconciliation

The agent's main reconcile loop runs each cycle. It keeps the `dips` rule for any deployment with a pending proposal or active agreement, and reaps rules for deployments no longer covered. The reaper SKIPS its pass when the indexing-payments subgraph lags chain head by more than 5 minutes (a freshness guard against reaping on stale data).

> 💡 Under automatic allocation management the agent keeps healthy DIPS allocations open and collects in place — it does not close and reopen them to get paid. Expect the same allocation id to persist across cycles.

### D-5.1 Deployment indexing healthy

**Objective**: The deployment indexes and is healthy on graph-node.

**Prerequisites**: D-3 complete (agreement `Accepted`, allocation Active).

**Steps**: Read deployment indexing health — graph-node index-node status API `indexingStatuses`. The status endpoint is environment-specific: on local-network it is graph-node port `8030` at `/graphql`; a testnet uses that operator's status endpoint. <!-- verify status endpoint for your env -->

```bash
curl -s "http://localhost:8030/graphql" -H 'content-type: application/json' \
  -d '{"query":"{ indexingStatuses(subgraphs:[\"<HASH>\"]){ synced health fatalError { message } chains { latestBlock { number } chainHeadBlock { number } } } }"}'
```

Healthy means `health == "healthy"`, no `fatalError`, and `latestBlock` synced to (or progressing toward) `chainHeadBlock`.

**Pass Criteria**:

- [ ] The deployment is indexing and healthy on graph-node — `indexingStatuses` for `<HASH>` returns `health` `healthy` with `synced`/progressing blocks. <!-- verify status endpoint for your env -->

---

### D-5.2 Agreement `Accepted` on subgraph

**Objective**: The agreement is tracked as `Accepted` on the indexing-payments subgraph.

**Prerequisites**: D-3 complete.

**Steps**: Observation toolbox "Agreement" (filter by `allocationId:"<ALLOC_ID>"`).

**Pass Criteria**:

- [ ] The agreement shows `Accepted` on the indexing-payments subgraph — Observation toolbox "Agreement" (filter by `allocationId:"<ALLOC_ID>"`; `state` is `1`).

---

### D-5.3 `dips` rule persists across reconcile cycles + allocation not auto-closed

**Objective**: The `dips` rule survives reconcile cycles and the backing allocation is not auto-closed.

**Prerequisites**: D-3 complete.

**Steps**: Wait at least two reconcile cycles, then re-check the rule and the allocation.

**Pass Criteria**:

- [ ] The `dips` rule for the deployment still exists after waiting ≥2 reconcile cycles — Observation toolbox "Indexing rules" (`decisionBasis == "dips"`, `identifier == <HASH>`).
- [ ] The allocation is still Active and was not auto-closed — Observation toolbox "Active allocation" (same allocation id as D-3).

---

## Cycle D-6 — Recurring collection

Each time `minSecondsPerCollection` elapses and the window opens, the agent submits `SubgraphService.collect` (recent-block POI + entity count, slippage limit applied), aiming near `--dips-collection-target` (default 50%) of the window. Drive at least 2–3 successive windows and confirm a collection each time.

**Prerequisites (cycle)**: D-5 — agreement `Accepted`, allocation Active, indexing healthy.

Capture pre-values, then advance one window and re-read; repeat per cycle:

- `lastCollectionAt` — Observation toolbox "On-chain agreement state" (`getAgreement`, 5th field).
- Escrow balance — Observation toolbox "Payer escrow balance".
- Advance a window — local-network `cast rpc --rpc-url "$RPC" anvil_mine <blocks> <interval>` (as in the time-advancement note); a testnet waits the real `minSecondsPerCollection`.

Read collection progress on the indexing-payments subgraph (Observation toolbox "Agreement"; `lastCollectionAt` advances each cycle):

```bash
curl -s "$INDEXING_PAYMENTS_SUBGRAPH_URL" -H 'content-type: application/json' \
  -d '{"query":"{ indexingAgreements(where:{ allocationId:\"<ALLOC_ID>\" }){ id state lastCollectionAt } }"}'
```

> ⚠️ Advance time across a bounded block count with large intervals (e.g. 100 blocks) rather than one block per second — minting too many epochs can trip allocation expiration (≈9-epoch limit) and close the allocation out from under the test.

### D-6.1 First collection includes `maxInitialTokens` bonus

**Objective**: The first collection includes `maxInitialTokens`, a one-time amount added only when `lastCollectionAt == 0`; later collections do not.

**Prerequisites**: An accepted agreement that has not yet collected (`lastCollectionAt == 0`).

**Steps**: Advance the first window and let the agent collect; capture the per-collection payout.

> 💡 First-collection bonus: the first collection includes `maxInitialTokens` (a one-time amount added only when `lastCollectionAt == 0`); later collections do not. If you can read the per-collection payout, confirm the first is larger by roughly `maxInitialTokens`.

**Pass Criteria**:

- [ ] The first collection's payout is larger by roughly `maxInitialTokens` than subsequent collections — confirmed when `lastCollectionAt` was `0` at collection time.
- [ ] The agent log shows `Successfully collected indexing fees`.

---

### D-6.2 Recurring collection across multiple windows

**Objective**: The agent collects repeatedly across successive collection windows; `lastCollectionAt` advances on-chain and on the subgraph.

**Prerequisites**: D-6.1 (first collection done). Indexing healthy.

**Steps**: Drive 2–3 successive windows (advance time per cycle as above) and confirm a collection each time.

**Pass Criteria**:

- [ ] `lastCollectionAt` advances on each successive window — both on-chain ("On-chain agreement state") and on the indexing-payments subgraph ("Agreement").
- [ ] The agreement stays `Accepted` (state `1`) and actively collecting across cycles — subgraph "Agreement".
- [ ] The agent log shows `Successfully collected indexing fees` once per cycle.

---

### D-6.3 Escrow drains cumulatively

**Objective**: The payer escrow balance decreases with each collection.

**Prerequisites**: D-6.2 in progress.

**Steps**: Re-run `getBalance(payer, recurringCollector, indexer)` per cycle and compare.

**Pass Criteria**:

- [ ] The payer escrow balance decreases with each collection (cumulative drain) — re-run `getBalance` per cycle and compare.

---

### D-6.4 Collection lands within window near `--dips-collection-target`

**Objective**: Each collection lands inside the window, near the configured target placement.

**Prerequisites**: D-6.2 in progress.

**Steps**: Observe where each collection lands relative to `[minSecondsPerCollection, maxSecondsPerCollection]`.

**Pass Criteria**:

- [ ] Each collection lands inside the window, near `--dips-collection-target` of `[minSecondsPerCollection, maxSecondsPerCollection]`.

---

### D-6.5 Payout scales with entity count

**Objective**: The collected amount scales with the deployment's entity count.

**Prerequisites**: D-6.2 in progress; a deployment whose entity count grows across windows.

**Steps**: Compare per-collection payouts as entities grow; payout tracks `collectionSeconds × (tokensPerSecond + tokensPerEntityPerSecond × entities)`.

**Pass Criteria**:

- [ ] The collected amount scales with entity count — payout tracks `collectionSeconds × (tokensPerSecond + tokensPerEntityPerSecond × entities)`; as entities grow, the per-collection amount grows.

---

## Cycle D-7 — Long-lived allocation protection

The deployment has a collectable DIPS agreement, so the agent refuses a normal close and never auto-closes the allocation. A forced close goes through and `SubgraphService` auto-cancels the active agreement in the same transaction (cancelled by ServiceProvider).

**Prerequisites (cycle)**: D-6 — an `Accepted`, collecting agreement with an Active allocation.

indexer-cli close — Horizon allocations need a POI and the epoch start block; use a zero POI as in D-3. The epoch start block comes from `EpochManager.currentEpochBlock()`:

```bash
EPOCH_BLOCK=$(cast call --rpc-url "$RPC" "$EPOCH_MANAGER" 'currentEpochBlock()(uint256)')
ZERO_POI=0x0000000000000000000000000000000000000000000000000000000000000000
# without --force → rejected
graph indexer allocations close <ALLOC_ID> "$ZERO_POI" "$EPOCH_BLOCK" --network <NETWORK>
# with --force → succeeds, cancels the agreement on-chain
graph indexer allocations close <ALLOC_ID> "$ZERO_POI" "$EPOCH_BLOCK" --force --network <NETWORK>
```

> ⚠️ `--force` is destructive — it ends the agreement on-chain. Run it last (D-7.3), or on a throwaway agreement/deployment. For an orderly opt-out that does a best-effort final collection first, prefer the `never` rule (D-8.3).

### D-7.1 Unallocate blocked without `--force`

**Objective**: The agent rejects a normal (non-forced) close of a DIPS-backed allocation; the allocation stays Active.

**Steps**: Attempt to close the backing allocation WITHOUT `--force`.

**Pass Criteria**:

- [ ] The non-forced close is rejected with a message about the deployment's DIPS agreement; the allocation remains Active — Observation toolbox "Active allocation".

---

### D-7.2 Allocation not auto-closed across reconcile

**Objective**: The agent never auto-closes the DIPS-backed allocation.

**Steps**: Confirm the allocation stays Active across a reconcile cycle.

**Pass Criteria**:

- [ ] After a reconcile cycle the allocation is still Active (not auto-closed) — Observation toolbox "Active allocation".

---

### D-7.3 Force-close cancels agreement on-chain (state `2`)

**Objective**: A forced close succeeds and `SubgraphService` cancels the agreement on-chain in the same transaction.

**Steps**: Retry the close WITH `--force`. The close succeeds and cancels the agreement on-chain.

**Pass Criteria**:

- [ ] The forced close succeeds and the agreement state becomes `CanceledByServiceProvider` (=2) — Observation toolbox "On-chain agreement state" (`getAgreement`), last field is `2`.

---

## Cycle D-8 — Cancellation

Two independent payer/SP cancellation paths plus the indexer opt-out. Each needs its own fresh `Accepted` agreement (D-7.3's forced close ended the earlier one); re-run D-2 and D-3 to set one up.

> ⚠️ Re-creating an agreement on the same deployment may be delayed by the ~15-minute recently-executed-action cooldown (Post-Testing Checklist). Use a different deployment if needed.

### D-8.1 Payer cancel → state `3` + final collection

**Objective**: The payer cancels on-chain; the agent keeps protecting the allocation and performs the periodic final collection until the on-chain window is drained.

**Prerequisites**: A fresh `Accepted`, collecting agreement (re-run D-2/D-3).

**Steps**: The payer cancels on-chain via `SubgraphService.cancelIndexingAgreementByPayer(bytes16)`, then advance time so the final collection window opens.

Payer cancel — payer key:

```bash
cast send --rpc-url "$RPC" --private-key "$PAYER_SECRET" \
  "$SUBGRAPH_SERVICE" "cancelIndexingAgreementByPayer(bytes16)" "<AGREEMENT_ID>"
```

Advance time so the final collection window opens — local-network with `cast rpc --rpc-url "$RPC" anvil_mine <blocks> <interval>` as in D-6; a testnet waits the real elapsed time.

**Pass Criteria**:

- [ ] The agreement state is `CanceledByPayer` (=3) — Observation toolbox "On-chain agreement state" (`getAgreement`), last field is `3`.
- [ ] After advancing time, the agent performs one more (final) collection — `lastCollectionAt` advances once more (Observation toolbox "On-chain agreement state", 5th field).

---

### D-8.2 Payer cancel → protection releases when non-collectable

**Objective**: Once the cancelled agreement is no longer collectable, protection releases and the agent lets the allocation close.

**Prerequisites**: D-8.1 — agreement `CanceledByPayer`, final collection drained.

**Steps**: Continue advancing time/cycles until the on-chain window is fully drained; observe the agent release protection and close the allocation.

**Pass Criteria**:

- [ ] Protection releases once the agreement is no longer collectable — Observation toolbox "On-chain collectability" (`getCollectionInfo` returns `false`), after which the allocation is allowed to close — Observation toolbox "Active allocation" (eventually empty for the deployment).

---

### D-8.3 Indexer opt-out (`never`) → SP cancel (state `2`) + rule reaped + allocation closed

**Objective**: Setting a `never` rule makes the agent run a best-effort final collection, cancel on-chain (ServiceProvider), reap the `dips` rule, and close the allocation.

**Prerequisites**: A fresh `Accepted`, collecting agreement (re-run D-2/D-3).

**Steps**: Set a `never` rule on the deployment. On its next cycle the agent runs a best-effort final collection, cancels the agreement on-chain (ServiceProvider), reaps the `dips` rule, and closes the allocation.

```bash
graph indexer rules stop <HASH> --network <NETWORK>   # 'never' (alias 'stop')
# restore afterward so the deployment pool stays re-runnable:
graph indexer rules set <HASH> decisionBasis always --network <NETWORK>
```

> 💡 An `offchain` rule has the same opt-out effect as `never`.

**Pass Criteria**:

- [ ] The agent cancels the agreement on-chain to `CanceledByServiceProvider` (=2) — Observation toolbox "On-chain agreement state" (`getAgreement`), last field is `2`.
- [ ] A best-effort final collection was attempted before cancel — check the agent log; `lastCollectionAt` may advance once if the window was open (Observation toolbox "On-chain agreement state", 5th field).
- [ ] The `dips` rule for the deployment is reaped — Observation toolbox "Indexing rules" (no `dips` rule for `<HASH>`).
- [ ] The allocation is closed — Observation toolbox "Active allocation" (empty for the deployment).

---

## Edge cases

Off-the-main-line behaviors that are not failures. Each is self-contained and optional. E-3 uses the same agent-boundary proposal injection described in Negative checks.

### E-1 Agent restart durability

**Objective**: DIPS state survives an indexer-agent restart.

**Prerequisites**: A queued `pending` proposal (not yet accepted) AND, separately, an already-accepted, collecting agreement.

**Steps**: Restart the indexer-agent.

**Pass Criteria**:

- [ ] The `pending` proposal is still present after restart and is accepted on a later cycle (→ `accepted`) — Observation toolbox "Pending proposal row".
- [ ] The accepted agreement resumes collecting after restart — `lastCollectionAt` advances on the next window (the collection tracker is rebuilt from the subgraph each cycle).
- [ ] The freshly-accepted-but-not-yet-indexed `dips` rule is not dropped across the restart — the rule for the deployment persists (Observation toolbox "Indexing rules").

---

### E-2 Late collection / downtime beyond the window max

**Objective**: `collectionSeconds` caps at `maxSecondsPerCollection`; extra elapsed time is forfeited, not errored.

**Prerequisites**: An accepted, collecting agreement.

**Steps**: Let chain time advance well beyond `maxSecondsPerCollection` before the agent collects (simulate downtime), then let it collect.

> 💡 Seconds beyond `maxSecondsPerCollection` are lost; the next window resumes normally from the capped point.

**Pass Criteria**:

- [ ] The collection succeeds (no error) and the payout reflects `collectionSeconds` capped at `maxSecondsPerCollection`, not the full elapsed time.
- [ ] No cancellation results from the lateness — state stays `Accepted` (`1`), Observation toolbox "On-chain agreement state".

---

### E-3 Two proposals for the same deployment in one tick

**Objective**: The accept loop dedupes per deployment and defers extras safely.

**Prerequisites**: Two `pending` proposals for the SAME deployment with no existing allocation (inject both — see the Negative checks injection note).

**Steps**: Let one acceptance cycle run, then a second.

**Pass Criteria**:

- [ ] Only one proposal is accepted in the first tick (the agent processes one per deployment to avoid racing the deterministic allocation id); the other stays `pending` — Observation toolbox "Pending proposal row".
- [ ] On the next tick the deferred proposal is accepted against the now-existing allocation (the D-3.1 reuse path) — both end `accepted`, sharing one allocation.

---

### E-4 Multiple concurrent agreements across deployments

**Objective**: Independent accept and collection across several agreements.

**Prerequisites**: 2–3 agreements proposed on different deployments at once (optionally make one underfunded to test isolation).

**Steps**: Let the agent accept and collect across cycles.

**Pass Criteria**:

- [ ] Each agreement is accepted independently — all proposals → `accepted` (the agent accepts up to 4 concurrently).
- [ ] Each agreement collects independently on its own window — `lastCollectionAt` advances per agreement (Observation toolbox "Agreement").
- [ ] A throttling/failing agreement (e.g. underfunded escrow) does not block collection on the others.

---

## Negative checks

Off-the-happy-path checks, each self-contained and optional. Run any subset; none depend on the others.

Several require feeding the agent a crafted/bad proposal or a fault condition the dipper would not produce on purpose. The cleanest way to drive these is at the agent boundary — encode a `SignedRCA` payload (empty signature) and insert a row directly into `pending_rca_proposals`, posting or omitting the on-chain offer as the check requires, rather than going through iisa/dipper.

For the error-name checks (N-3/N-4/N-5) the observable is the agent log line for the throttled failure plus the on-chain revert reason; where a state read clarifies, use the Observation toolbox (`getCollectionInfo`, `getAgreement`, `getBalance`, `getAllocation`). All three revert reasons are documented in [common errors](https://github.com/graphprotocol/indexer/blob/main/docs/dips/dips-common-errors.md). _(TODO: fix link)_

### N-1 Deadline-expired proposal

**Objective**: A proposal whose RCA `deadline` is in the past is rejected and its `dips` rule cleaned up.

**Prerequisites**: Inject a `pending_rca_proposals` row whose RCA `deadline` is in the past (`insert_proposal` with an `encode_rca` payload carrying an elapsed deadline). No on-chain offer is required.

**Steps**: Let the acceptance loop run (`--dips-acceptance-interval`).

**Pass Criteria**:

- [ ] The proposal flips to `rejected` — toolbox "Pending proposal row" (status `rejected`); agent log notes `deadline_expired`.
- [ ] The `dips` rule is cleaned up — toolbox "Indexing rules" (no `dips` rule for the deployment).

---

### N-2 Offer never posted

**Objective**: A queued proposal with no on-chain offer stays `pending`; the offer pre-flight returns not-yet.

**Prerequisites**: Inject a queued `pending_rca_proposals` row (status `pending`) for a valid future-deadline RCA but DO NOT post the on-chain offer (`insert_proposal`, skipping `post_rca_offer_on_chain`).

**Steps**: Let the acceptance loop run for several cycles.

**Pass Criteria**:

- [ ] The proposal stays `pending` across several cycles — toolbox "Pending proposal row" (status remains `pending`); the offer pre-flight returns not-yet.
- [ ] The agent log notes the offer is not yet on the subgraph — `Offer not yet on subgraph; leaving proposal pending` (`not_yet`).

---

### N-3 Excessive slippage

**Objective**: `collect` reverts with `RecurringCollectorExcessiveSlippage` when the data-service request exceeds the per-collection cap by more than tolerance; the agent throttles retries without cancelling.

**Prerequisites**: Drive the data-service request past the agreement's per-collection cap by more than the tolerance: set `--dips-collection-slippage` low (e.g. `0`) and let the deployment's entity count grow, so the per-entity ask (`tokensPerEntityPerSecond × entities`) outpaces `maxOngoingTokensPerSecond`.

**Steps**: Let `minSecondsPerCollection` elapse and the collection loop fire.

**Pass Criteria**:

- [ ] `SubgraphService.collect` reverts with `RecurringCollectorExcessiveSlippage` — agent log shows the throttled failure; see [common errors](https://github.com/graphprotocol/indexer/blob/main/docs/dips/dips-common-errors.md#recurringcollectorexcessiveslippage). _(TODO: fix link)_
- [ ] The agent throttles retries and does NOT cancel the agreement — `getAgreement` state stays `1` (Accepted).
- [ ] Collection resumes once terms fit — raise `--dips-collection-slippage` (or let the cap catch up); next cycle collects and `lastCollectionAt` advances.

---

### N-4 Escrow underfunded

**Objective**: `collect` reverts with `PaymentsEscrowInsufficientBalance` when escrow is below the amount owed; the agent throttles without cancelling.

**Prerequisites**: Bring the payer escrow below the amount owed for the next collection — confirm with the Observation toolbox "Payer escrow balance" read.

**Steps**: Let `minSecondsPerCollection` elapse and the collection loop fire.

**Pass Criteria**:

- [ ] `collect` reverts with `PaymentsEscrowInsufficientBalance` — agent log shows the throttled failure; see [common errors](https://github.com/graphprotocol/indexer/blob/main/docs/dips/dips-common-errors.md#paymentsescrowinsufficientbalance). _(TODO: fix link)_
- [ ] The agent throttles retries (no cancel) — `getAgreement` state stays `1`.
- [ ] After the payer tops up escrow, the next cycle collects — `getBalance` decreases and `lastCollectionAt` advances.

---

### N-5 Missing provision

**Objective**: `collect` reverts with `RecurringCollectorUnauthorizedDataService` when the service provider has no active provision; collection resumes once restored.

**Prerequisites**: Remove or lapse the indexer's `SubgraphService` provision so the service provider has no active provision at collection time.

**Steps**: Let `minSecondsPerCollection` elapse and the collection loop fire.

**Pass Criteria**:

- [ ] `collect` reverts with `RecurringCollectorUnauthorizedDataService` — agent log shows the throttled failure; see [common errors](https://github.com/graphprotocol/indexer/blob/main/docs/dips/dips-common-errors.md#recurringcollectorunauthorizeddataservice). _(TODO: fix link)_
- [ ] After the provision is restored (`graph indexer provision add ...`), collection succeeds next cycle — `lastCollectionAt` advances.

---

### N-6 Stale indexing-payments subgraph

**Objective**: When the indexing-payments subgraph lags chain head by more than 5 minutes, the rule reaper is skipped while acceptance and collection continue.

**Prerequisites**: Pause the indexing-payments subgraph on graph-node (graph-node admin JSON-RPC `subgraph_pause`) and let it fall more than 5 minutes behind chain head.

**Steps**: Let the main reconcile loop run while the subgraph lags; meanwhile let acceptance and collection continue.

**Pass Criteria**:

- [ ] The agent logs `Skipping DIPS rule cleanup: indexing-payments subgraph is stale or unreadable`.
- [ ] `dips` rules are NOT reaped — toolbox "Indexing rules" still shows the `dips` rule for `<HASH>`.
- [ ] Acceptance and collection are unaffected — proposals still accept and `lastCollectionAt` still advances.
- [ ] Resume the subgraph afterward (`subgraph_resume`); the next cycle resumes normal rule cleanup.

---

### N-7 Offer hash mismatch

**Objective**: A proposal whose RCA terms differ from the posted on-chain offer is rejected with `offer_hash_mismatch` and not retried.

**Prerequisites**: Post an on-chain offer whose `offerHash` differs from the agent's locally-computed RCA hash: queue a proposal whose RCA terms differ from the posted offer for the same agreement id (inject an `encode_rca` payload, then `post_rca_offer_on_chain` with mismatched terms, or vice versa).

**Steps**: Let the acceptance loop run; the offer pre-flight finds the on-chain offer and compares hashes.

**Pass Criteria**:

- [ ] The proposal flips to `rejected` with reason `offer_hash_mismatch` — toolbox "Pending proposal row" (status `rejected`); agent log notes the hash mismatch.
- [ ] The proposal is not retried — status stays `rejected` across cycles.

---

## Post-Testing Checklist

Leave the environment in a re-runnable state.

- [ ] Restore `always`/default rules on any deployment set to `never`/`offchain` during the run:

  ```bash
  graph indexer rules set <HASH> decisionBasis always --network <NETWORK>
  ```

- [ ] Close any test allocations still open — indexer-cli close (zero POI + `EpochManager.currentEpochBlock()` as in D-7).
- [ ] Delete test proposal rows if you injected/queued any, via the Prerequisites psql connection:

  ```bash
  psql -h "$PG_HOST" -p "$PG_PORT" -U postgres -d indexer_components_1 \
    -c "DELETE FROM pending_rca_proposals WHERE ...;"
  ```

- [ ] Undeny any deployment denied in D-4 — `RewardsManager.setDenied(<DEPLOYMENT_BYTES32>, false)` from the oracle key.

> ⚠️ After closing an allocation the agent will not re-allocate that same deployment for roughly 15 minutes (recently-executed-action cooldown). Re-running cancel scenarios immediately on the same deployment will stall; use a different deployment or wait out the cooldown.

---

## Coverage map

Every documented DIPS behavior maps to a test. Sourced from the DIPS feature docs in the [indexer repo](https://github.com/graphprotocol/indexer/tree/main/docs/dips).

| Area | Behavior | Test |
| --- | --- | --- |
| Acceptance & proposals | Valid proposal accepted on-chain | D-3.1, D-3.2 |
| Acceptance & proposals | Deadline-expired proposal rejected | N-1 |
| Acceptance & proposals | Offer not yet on subgraph → stays pending | N-2 |
| Acceptance & proposals | Offer hash mismatch rejected | N-7 |
| Indexing rules | `dips` rule created on accept | D-3.1, D-3.2, D-5.3 |
| Indexing rules | Rule reaped when agreement ends | D-8.3 |
| Indexing rules | Stale-subgraph guard skips reaper | N-6 |
| Allocation & sizing | Existing allocation reused | D-3.1 |
| Allocation & sizing | New allocation via multicall | D-3.2 |
| Allocation & sizing | Reward-earning sizing | D-4.1 |
| Allocation & sizing | Rewards-denied sizing | D-4.2 |
| Allocation & sizing | Zero-token allocation valid | D-4.2 |
| Collection | First-collection `maxInitialTokens` bonus | D-6.1 |
| Collection | Recurring collection across windows | D-6.2 |
| Collection | Collection reflected on indexing-payments subgraph | D-6.2 |
| Collection | Escrow drains cumulatively | D-6.3 |
| Collection | Collection within window + target placement | D-6.4 |
| Collection | Payout scales with entity count | D-6.5 |
| Collection | Excessive slippage revert + throttle | N-3 |
| Collection | Escrow underfunded | N-4 |
| Collection | Missing provision unauthorized | N-5 |
| Collection | Zero-POI fallback | D-6.2, N-5 |
| Protection | Unallocate blocked without force | D-7.1 |
| Protection | Allocation not auto-closed | D-5.3, D-7.2 |
| Protection | Force-close cancels on-chain | D-7.3 |
| Cancellation | Payer cancel + periodic final collection | D-8.1 |
| Cancellation | Protection releases when non-collectable | D-8.2 |
| Cancellation | Indexer opt-out + SP cancel | D-8.3 |
| Config/tuning | `--dips-collection-target` | D-6.4 |
| Config/tuning | `--dips-collection-slippage` | N-3 |
| Config/tuning | `--dips-acceptance-interval` | D-3.1 |
| Config/tuning | `--dips-allocation-amount` | D-4.2 |
| Edge cases | Agent restart durability | E-1 |
| Edge cases | Late collection beyond window max | E-2 |
| Edge cases | Two proposals, same deployment, one tick | E-3 |
| Edge cases | Concurrent agreements across deployments | E-4 |

---

## Related Documentation

- [← Back to DIPS testing](./README.md)
- [TestnetDetails.md](./TestnetDetails.md) — Arbitrum Sepolia network details
- [MainnetDetails.md](./MainnetDetails.md) — Arbitrum One network details (mainnet-pending)
- [LocalNetworkDetails.md](./LocalNetworkDetails.md) — local-network setup and dynamic addresses
- [DIPS indexer guide](https://github.com/graphprotocol/indexer/blob/main/docs/dips/dips-indexer-guide.md) — indexer-facing DIPS feature guide (indexer repo) _(TODO: fix link)_
- [DIPS quick reference](https://github.com/graphprotocol/indexer/blob/main/docs/dips/dips-quick-reference.md) — DIPS quick reference (indexer repo) _(TODO: fix link)_
- [DIPS common errors](https://github.com/graphprotocol/indexer/blob/main/docs/dips/dips-common-errors.md) — DIPS error reference (indexer repo) _(TODO: fix link)_

---

_Derived from the DIPS indexer docs. Source: indexer-agent DipsManager (`packages/indexer-common/src/indexing-fees/dips.ts`), Horizon `RecurringCollector` / `SubgraphService`._
