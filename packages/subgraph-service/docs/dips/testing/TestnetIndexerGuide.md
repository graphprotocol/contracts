# DIPS Testnet Indexer Guide

> **Status**: Testnet-only. DIPS is deployed on Arbitrum Sepolia; mainnet (Arbitrum One) is pending (`RecurringCollector` not yet deployed).
>
> **Navigation**: [← Back to DIPS testing](./README.md) | [TestnetDetails](./TestnetDetails.md)

You run a DIPS-enabled indexer stack on testnet — indexer-service plus indexer-agent — and verify it correctly accepts agreements offered to you, collects payment over time, and handles cancellation. The payer side (`iisa`/`dipper`) that originates proposals and triggers the on-chain offer (posted via RAM) is operated by someone else; you rely on it but do not run it. This guide covers only the actions an indexer can take on their own stack.

DIPS is deployed on Arbitrum Sepolia (mainnet-pending).

---

## Required components

No official releases yet — all versions are TBD. Only indexer-service and indexer-agent change from a normal indexer setup.

| Component | Version |
| --- | --- |
| indexer-agent | TBD |
| indexer-service | TBD |
| indexing-payments subgraph (deployment hash / ID) | TBD |

---

## Testnet configuration values

Network and protocol values the tests depend on. See [TestnetDetails](./TestnetDetails.md) for the full network parameters and contract addresses.

| Parameter | Value |
| --- | --- |
| Epoch length | ~554 blocks (~110 minutes) |
| Max allocation lifetime | 8 epochs (~15 hours) |
| POI staleness threshold (`maxPOIStaleness`) | 28800 s (8 hours) — `SubgraphService.maxPOIStaleness()` |
| DIPS collection window min (`minSecondsPerCollection`) | TBD |
| DIPS collection window max (`maxSecondsPerCollection`) | TBD |
| `maxInitialTokens` (first-collection bonus) | TBD |

---

## Testnet subgraphs

The list of subgraphs available on testnet for DIPS. Use it to choose which subgraph to pre-allocate (see [Pre-run allocation setup](#pre-run-allocation-setup)).

| # | Deployment ID | Rewards | Use |
| --- | --- | --- | --- |
| 1 | TBD | enabled | Pre-allocate before running — existing-allocation path (T-1.1) |
| 2 | TBD | enabled | Leave unallocated — new-allocation path (T-1.2) + reward sizing (T-2.1) |
| 3 | TBD | denied | Leave unallocated — rewards-denied sizing (T-2.2) |

---

## Prerequisites

Confirm each before running the tests.

> 💡 Contract addresses and the RPC come from [TestnetDetails](./TestnetDetails.md). The commands below use shell variables for those values: contracts (`$RPC`, `$SUBGRAPH_SERVICE`, `$RECURRING_COLLECTOR`, `$REWARDS_MANAGER`, `$EPOCH_MANAGER`), accounts (`$INDEXER`), and endpoints (`$AGENT_URL`, `$NETWORK_SUBGRAPH_URL`, `$INDEXING_PAYMENTS_SUBGRAPH_URL`).

- [ ] Indexer staked and provisioned in `SubgraphService` (active provision).
- [ ] indexer-agent started with `--enable-dips true` and an indexing-payments subgraph configured (`--indexing-payments-subgraph-endpoint` or `--indexing-payments-subgraph-deployment`).

  Agent healthy:

  ```bash
  curl -s "$AGENT_URL" -H 'content-type: application/json' \
    -d '{"query":"{ indexingRules(merged:false){ identifier } }"}' | jq -e '.data'
  ```

- [ ] Network subgraph and indexing-payments subgraph synced to chain head.

  ```bash
  curl -s "$NETWORK_SUBGRAPH_URL" -H 'content-type: application/json' \
    -d '{"query":"{ _meta { block { number } } }"}' | jq -r '.data._meta.block.number'
  ```

---

## How selection works

You do not control which agreements you get. IISA (payer-side) selects the indexer for each deployment — the payer supplies only the deployment, chain, and candidate count, and cannot target a specific indexer. There is no indexer-side admin call to request an agreement.

On the small testnet (few indexers), expect an agreement to be offered to you fairly quickly once you run a DIPS-enabled stack. No special action is needed beyond running the stack. Your only setup lever is which subgraphs you pre-allocate (next section).

---

## Pre-run allocation setup

Before (or while) running the DIPS agent, set up the three subgraphs from the [Testnet subgraphs](#testnet-subgraphs) table so each path gets exercised when agreements arrive. Use each row's Deployment ID:

- **Subgraph #1** (rewards enabled) — **open an allocation** before running. An agreement for it exercises the existing-allocation accept path, the agent reusing the open allocation (T-1.1).
- **Subgraph #2** (rewards enabled) — **leave unallocated**. An agreement exercises the new-allocation accept path (the agent opens an allocation via multicall on accept) and reward-earning sizing (T-1.2, T-2.1).
- **Subgraph #3** (rewards denied) — **leave unallocated**. Exercises rewards-denied sizing (T-2.2).

Open the allocation on **Subgraph #1** — indexer-cli action queue. Use Subgraph #1's Deployment ID from the table as `<HASH>`:

```bash
graph indexer actions queue allocate <HASH> <AMOUNT> --network <NETWORK>   # <HASH> = Subgraph #1 Deployment ID
graph indexer actions approve
```

Confirm the active allocation — network subgraph:

```bash
curl -s "$NETWORK_SUBGRAPH_URL" -H 'content-type: application/json' \
  -d '{"query":"{ allocations(where:{ subgraphDeployment_:{ipfsHash:\"<HASH>\"}, status:Active }, orderBy:createdAt, orderDirection:desc, first:1){ id } }"}'
```

> **GraphQL note**: addresses in subgraph queries must be lowercase.

---

## Observation toolbox

Read commands referenced throughout. Replace `<HASH>`, `<ALLOC_ID>`, `<AGREEMENT_ID>` with the values for your run.

Indexing rules — agent management API:

```bash
curl -s "$AGENT_URL" -H 'content-type: application/json' \
  -d '{"query":"{ indexingRules(merged:false){ identifier decisionBasis allocationAmount } }"}'
```

Active allocation for a deployment — network subgraph:

```bash
curl -s "$NETWORK_SUBGRAPH_URL" -H 'content-type: application/json' \
  -d '{"query":"{ allocations(where:{ subgraphDeployment_:{ipfsHash:\"<HASH>\"}, status:Active }, orderBy:createdAt, orderDirection:desc, first:1){ id } }"}'
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

---

## Test Sequence Overview

| Set | Area | Tests |
| --- | --- | --- |
| T-1 | Receive and accept | T-1.1 – T-1.2 |
| T-2 | Allocation sizing | T-2.1 – T-2.2 |
| T-3 | Recurring collection | T-3.1 – T-3.3 |
| T-4 | Long-lived allocation protection | T-4.1 – T-4.2 |
| T-5 | Cancellation | T-5.1 – T-5.2 |

Each test follows: **Objective / Prerequisites (when relevant) / Steps / Pass Criteria**. Time waits are real elapsed time on testnet.

---

## Set T-1 — Receive and accept

The agent's acceptance loop runs every `--dips-acceptance-interval` (default 5s). Each pass confirms the offer is on the indexing-payments subgraph, then calls `SubgraphService.acceptIndexingAgreement`. The two tests differ only in whether an active allocation already exists for the deployment.

### T-1.1 Accept on a pre-allocated subgraph (existing-allocation path)

**Objective**: The agent accepts an agreement offered for a deployment that already has an active allocation, reusing that allocation with a single `acceptIndexingAgreement` tx.

**Prerequisites**: An active allocation already open for the deployment (the reward-earning subgraph from [Pre-run allocation setup](#pre-run-allocation-setup)). An agreement has been offered to you (IISA selected you).

**Steps**: Let the acceptance loop run.

**Pass Criteria**:

- [ ] A `dips` indexing rule exists for the deployment — toolbox "Indexing rules", `decisionBasis == "dips"` and `identifier == <HASH>`.
- [ ] The pre-existing allocation id is reused (no new allocation) — toolbox "Active allocation".
- [ ] On-chain agreement state is `Accepted` (=1) — toolbox "On-chain agreement state" (`getAgreement`), last field is `1`.

---

### T-1.2 Accept on an unallocated subgraph (new-allocation path)

**Objective**: With no allocation present, the agent opens one atomically via `multicall(startService, acceptIndexingAgreement)` when accepting.

**Prerequisites**: No active allocation for the deployment (the target subgraph you left unallocated). An agreement has been offered to you.

**Steps**: Let the acceptance loop run.

**Pass Criteria**:

- [ ] A `dips` indexing rule exists for the deployment — toolbox "Indexing rules", `decisionBasis == "dips"` and `identifier == <HASH>`.
- [ ] A new active allocation id appears for the deployment — toolbox "Active allocation".
- [ ] On-chain agreement state is `Accepted` (=1) — toolbox "On-chain agreement state" (`getAgreement`), last field is `1`.

---

## Set T-2 — Allocation sizing

The agent sizes the DIPS allocation by whether the deployment earns indexing rewards. An indexer cannot deny a subgraph (that is a subgraph-availability-oracle action), so T-2.2 applies only if you happen to receive an agreement for a rewards-denied subgraph from the testnet list.

### T-2.1 Reward-earning subgraph sizing

**Objective**: A reward-earning deployment's allocation uses the deployment's indexing-rule `allocationAmount`, or `defaultAllocationAmount` if the rule has none.

**Prerequisites**: An accepted agreement on a reward-earning deployment (T-1.1 or T-1.2).

**Steps**: Read allocation tokens — toolbox "Allocation tokens" (`getAllocation`), `tokens` is the 3rd field.

**Pass Criteria**:

- [ ] The allocation `tokens` equals the rule's `allocationAmount` (or `defaultAllocationAmount` when the rule sets none).

---

### T-2.2 Rewards-denied subgraph sizing

**Objective**: If you receive an agreement for a rewards-denied subgraph from the testnet list, the allocation uses `--dips-allocation-amount` (env `INDEXER_AGENT_DIPS_ALLOCATION_AMOUNT`), default `0`. A zero-token allocation is valid for DIPS — collection pays the RCA amount, independent of allocation size.

**Prerequisites**: An accepted agreement on a rewards-denied deployment from the testnet list.

**Steps**: Read allocation tokens — toolbox "Allocation tokens" (`getAllocation`), `tokens` is the 3rd field.

Confirm the deployment is rewards-denied:

```bash
cast call --rpc-url "$RPC" "$REWARDS_MANAGER" "isDenied(bytes32)(bool)" "<DEPLOYMENT_BYTES32>"
# → true
```

**Pass Criteria**:

- [ ] The allocation `tokens` equals `--dips-allocation-amount` (default `0` → a valid zero-token allocation).

---

## Set T-3 — Recurring collection

Each time `minSecondsPerCollection` elapses and the window opens, the agent submits `SubgraphService.collect` (recent-block POI + entity count, slippage limit applied), aiming near `--dips-collection-target` (default 50%) of the window. Time waits are real elapsed time.

**Prerequisites (set)**: An `Accepted` agreement with an Active allocation and the deployment indexing healthy.

Before each window, capture the pre-value of `lastCollectionAt` (toolbox "On-chain agreement state", 5th field); wait the real `minSecondsPerCollection`, then re-read. Also read collection progress on the indexing-payments subgraph:

```bash
curl -s "$INDEXING_PAYMENTS_SUBGRAPH_URL" -H 'content-type: application/json' \
  -d '{"query":"{ indexingAgreements(where:{ allocationId:\"<ALLOC_ID>\" }){ id state lastCollectionAt } }"}'
```

### T-3.1 First collection includes the `maxInitialTokens` bonus

**Objective**: The first collection includes `maxInitialTokens`, a one-time amount added only when `lastCollectionAt == 0`; later collections do not.

**Prerequisites**: An accepted agreement that has not yet collected (`lastCollectionAt == 0`).

**Steps**: Wait for the first window to open and let the agent collect; capture the per-collection payout.

**Pass Criteria**:

- [ ] The first collection's payout is larger by roughly `maxInitialTokens` than subsequent collections — confirmed when `lastCollectionAt` was `0` at collection time.
- [ ] The agent log shows `Successfully collected indexing fees`.

---

### T-3.2 Recurring collection across multiple windows

**Objective**: The agent collects repeatedly across successive windows; `lastCollectionAt` advances on-chain and on the subgraph.

**Prerequisites**: T-3.1 (first collection done). Indexing healthy.

**Steps**: Wait through 2–3 successive windows (real `minSecondsPerCollection` each) and confirm a collection each time.

**Pass Criteria**:

- [ ] `lastCollectionAt` advances on each successive window — both on-chain (toolbox "On-chain agreement state") and on the indexing-payments subgraph (toolbox "Agreement").
- [ ] The agreement stays `Accepted` (state `1`) and actively collecting across windows.
- [ ] The agent log shows `Successfully collected indexing fees` once per window.

---

### T-3.3 Collection lands within the window near `--dips-collection-target`

**Objective**: Each collection lands inside the window, near the configured target placement.

**Prerequisites**: T-3.2 in progress.

**Steps**: Observe where each collection lands relative to `[minSecondsPerCollection, maxSecondsPerCollection]`.

**Pass Criteria**:

- [ ] Each collection lands inside the window, near `--dips-collection-target` of `[minSecondsPerCollection, maxSecondsPerCollection]`.

---

## Set T-4 — Long-lived allocation protection

A deployment with a collectable DIPS agreement is protected: the agent refuses a normal close and never auto-closes the allocation. A forced close goes through and `SubgraphService` auto-cancels the agreement in the same transaction.

**Prerequisites (set)**: An `Accepted`, collecting agreement with an Active allocation.

indexer-cli close — Horizon allocations need a POI and the epoch start block; use a zero POI with `--force`. The epoch start block comes from `EpochManager.currentEpochBlock()`:

```bash
EPOCH_BLOCK=$(cast call --rpc-url "$RPC" "$EPOCH_MANAGER" 'currentEpochBlock()(uint256)')
ZERO_POI=0x0000000000000000000000000000000000000000000000000000000000000000
# without --force → rejected
graph indexer allocations close <ALLOC_ID> "$ZERO_POI" "$EPOCH_BLOCK" --network <NETWORK>
# with --force → succeeds, cancels the agreement on-chain
graph indexer allocations close <ALLOC_ID> "$ZERO_POI" "$EPOCH_BLOCK" --force --network <NETWORK>
```

> ⚠️ `--force` is destructive — it ends the agreement on-chain. Run T-4.2 last, or on a throwaway agreement. For an orderly opt-out that does a best-effort final collection first, prefer the `never` rule (T-5.1).

### T-4.1 Unallocate blocked without `--force`

**Objective**: The agent rejects a normal (non-forced) close of a DIPS-backed allocation; the allocation stays Active.

**Steps**: Attempt to close the backing allocation WITHOUT `--force`.

**Pass Criteria**:

- [ ] The non-forced close is rejected with a message about the deployment's DIPS agreement; the allocation remains Active — toolbox "Active allocation".

---

### T-4.2 Force-close cancels the agreement on-chain (state `2`)

**Objective**: A forced close succeeds and `SubgraphService` cancels the agreement on-chain in the same transaction.

**Steps**: Retry the close WITH `--force`.

**Pass Criteria**:

- [ ] The forced close succeeds and the agreement state becomes `CanceledByServiceProvider` (=2) — toolbox "On-chain agreement state" (`getAgreement`), last field is `2`.

---

## Set T-5 — Cancellation

The indexer opt-out path plus an observation of the payer-cancel path. T-5.1 needs a fresh `Accepted` agreement; if T-4.2's forced close ended your earlier one, wait for a new offer (selection is out of your control) or use a different deployment.

> ⚠️ Re-allocating the same deployment may be delayed by the ~15-minute recently-executed-action cooldown. Use a different deployment if needed.

### T-5.1 Opt out via a `never` rule

**Objective**: Setting a `never` rule makes the agent run a best-effort final collection, cancel on-chain (ServiceProvider), reap the `dips` rule, and close the allocation.

**Prerequisites**: A fresh `Accepted`, collecting agreement.

**Steps**: Set a `never` rule on the deployment. On its next cycle the agent runs a best-effort final collection, cancels the agreement on-chain (ServiceProvider), reaps the `dips` rule, and closes the allocation.

```bash
graph indexer rules stop <HASH> --network <NETWORK>   # 'never' (alias 'stop')
# restore afterward so the deployment stays re-runnable:
graph indexer rules set <HASH> decisionBasis always --network <NETWORK>
```

> 💡 An `offchain` rule has the same opt-out effect as `never`.

**Pass Criteria**:

- [ ] The agent cancels the agreement on-chain to `CanceledByServiceProvider` (=2) — toolbox "On-chain agreement state" (`getAgreement`), last field is `2`.
- [ ] A best-effort final collection was attempted before cancel — check the agent log; `lastCollectionAt` may advance once if the window was open (toolbox "On-chain agreement state", 5th field).
- [ ] The `dips` rule for the deployment is reaped — toolbox "Indexing rules" (no `dips` rule for `<HASH>`).
- [ ] The allocation is closed — toolbox "Active allocation" (empty for the deployment).

---

### T-5.2 (Observe) Payer cancels

**Objective**: When the payer cancels on-chain, the agent keeps protecting the allocation, performs a final collection until the on-chain window is drained, then releases protection and closes the allocation. This is driven by the payer — observe only.

**Prerequisites**: A fresh `Accepted`, collecting agreement, and the payer cancels it (`SubgraphService.cancelIndexingAgreementByPayer`).

**Steps**: After the payer cancels, wait through the next window(s) and observe.

**Pass Criteria**:

- [ ] The agreement state is `CanceledByPayer` (=3) — toolbox "On-chain agreement state" (`getAgreement`), last field is `3`.
- [ ] The agent performs one more (final) collection while still collectable — `lastCollectionAt` advances once more (toolbox "On-chain agreement state", 5th field).
- [ ] Once the agreement is no longer collectable, protection releases and the allocation is allowed to close — toolbox "On-chain collectability" (`getCollectionInfo` returns `false`), then toolbox "Active allocation" (eventually empty for the deployment).

---

## What to watch for

Collection can fail deterministically for reasons outside your control. When it does, the agent throttles and retries — it does **not** cancel the agreement, and you do not need to take action. The agreement stays `Accepted` (state `1`) and collection resumes once the condition clears. Common errors you might see in the agent log:

- `RecurringCollectorExcessiveSlippage` — the data-service request exceeded the per-collection cap by more than tolerance.
- `PaymentsEscrowInsufficientBalance` — the payer's escrow is below the amount owed.
- `RecurringCollectorUnauthorizedDataService` — the service provider has no active provision at collection time.

See [DIPS common errors](https://github.com/graphprotocol/indexer/blob/main/docs/dips/dips-common-errors.md) for each error and what clears it. _(TODO: fix link)_

---

## Post-run checklist

- [ ] Restore `always`/default rules on any deployment you set to `never`/`offchain`:

  ```bash
  graph indexer rules set <HASH> decisionBasis always --network <NETWORK>
  ```

> ⚠️ After closing an allocation the agent will not re-allocate that same deployment for roughly 15 minutes (recently-executed-action cooldown). Re-running cancellation scenarios immediately on the same deployment will stall; use a different deployment or wait out the cooldown.

---

## Related Documentation

- [← Back to DIPS testing](./README.md)
- [TestnetDetails.md](./TestnetDetails.md) — Arbitrum Sepolia network details
- [DIPS indexer guide](https://github.com/graphprotocol/indexer/blob/main/docs/dips/dips-indexer-guide.md) — indexer-facing DIPS feature guide (indexer repo) _(TODO: fix link)_
- [DIPS quick reference](https://github.com/graphprotocol/indexer/blob/main/docs/dips/dips-quick-reference.md) — DIPS quick reference (indexer repo) _(TODO: fix link)_
- [DIPS common errors](https://github.com/graphprotocol/indexer/blob/main/docs/dips/dips-common-errors.md) — DIPS error reference (indexer repo) _(TODO: fix link)_

---

_Derived from the DIPS integration test plan and the DIPS indexer docs. Source: indexer-agent DipsManager (`packages/indexer-common/src/indexing-fees/dips.ts`), Horizon `RecurringCollector` / `SubgraphService`._
