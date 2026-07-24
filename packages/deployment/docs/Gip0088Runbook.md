# GIP-0088 Full Rollout Runbook

Operational runbook for the GIP-0088 protocol upgrade. For what each script
does, see [Gip0088.md](Gip0088.md).

Run once per target environment, starting with a fork rehearsal. The fork
rehearsal runs Phases A–C only; Phase D applies to non-fork runs. See
[Environments](#environments) for the targets currently in scope.

A **stage** is an action that changes system state. A **gate** is a check
between two stages — postcondition of the previous, precondition of the next.
Sequencing follows gates, not numbers: new work is a stage inserted between
two gates.

**Invariant.** A gate's `Postcondition of` / `Precondition of` fields must
match the adjacent stages' `Exit gate` / `Entry gate` fields. Bidirectional
naming is the source of truth for ordering.

## Stage & Gate index

| Phase                                              | Stages                                                                                                                | Gates                                                                                                            |
| -------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Entry — Readiness                                  | —                                                                                                                     | [G1](#gate-g1)                                                                                                   |
| A — Contract deployment                            | [S1](#stage-s1) [S2](#stage-s2) [S3](#stage-s3)                                                                       | [G2](#gate-g2) [G3](#gate-g3) [G4](#gate-g4)                                                                     |
| B — Proxy upgrade                                  | [S4](#stage-s4) [S5](#stage-s5)                                                                                       | [G5](#gate-g5) [G6](#gate-g6)                                                                                    |
| C — Activation                                     | [S5a](#stage-s5a) [S6](#stage-s6) [S7](#stage-s7) [S8](#stage-s8) [S9](#stage-s9) [S10](#stage-s10) [S11](#stage-s11) | [G6a](#gate-g6a) [G7](#gate-g7) [G8](#gate-g8) [G9](#gate-g9) [G10](#gate-g10) [G11](#gate-g11) [G12](#gate-g12) |
| D — Off-chain & close-out (testnet / mainnet only) | [S12](#stage-s12) [S13](#stage-s13) [S14](#stage-s14) [S15](#stage-s15)                                               | [G13](#gate-g13) [G14](#gate-g14) [G15](#gate-g15) [G16](#gate-g16)                                              |

## Environments

Stages S5, S7, S9, S11 (sign & execute) differ per environment:

| Environment    | `<network>`       | Governance execution                                                     | Pace    | Reference                                                                                               |
| -------------- | ----------------- | ------------------------------------------------------------------------ | ------- | ------------------------------------------------------------------------------------------------------- |
| Fork rehearsal | `localhost`       | `deploy:execute-governance` impersonates the governor                    | instant | [GovernanceWorkflow.md — Fork Mode](GovernanceWorkflow.md#fork-mode-testing)                            |
| Testnet        | `arbitrumSepolia` | `deploy:execute-governance` signs with the governor EOA key              | minutes | [GovernanceWorkflow.md — Testnet Mode](GovernanceWorkflow.md#testnet-mode-with-eoa-governor)            |
| Mainnet        | `arbitrumOne`     | TX batch uploaded to the council Safe; reviewed, signed M-of-N, executed | days    | [GovernanceWorkflow.md — Mainnet Mode](GovernanceWorkflow.md#mainnetproduction-mode-with-safe-multisig) |

On fork, append `--skip-prompts` to every `deploy` command.

---

## Entry — Readiness

<a id="gate-g1"></a>

### Gate G1 — readiness

| Field            | Value                 |
| ---------------- | --------------------- |
| Postcondition of | — (entry)             |
| Precondition of  | [Stage S1](#stage-s1) |

**Check.** The operator confirms each of:

1. The working tree is checked out at the intended deployment-target commit;
   record its sha in the run record's `Runbook revision` field. Subsequent
   gates reference _this_ runbook revision.
2. `pnpm hardhat deploy:status --network <network>` runs clean (expect a
   "not started" picture for GIP-0088 on the first run; on later runs, the
   picture matches the prior environment's end-state).
3. `config/<network>.json5` has been reviewed for this network — issuance
   rates, REO parameters, pause guardians match the GIP-0088 specification.
4. Deployer EOA on `<network>` is funded with enough gas.
5. Deployer key is accessible — keystore unlocked or env var set
   (`<NETWORK>_DEPLOYER_KEY`).
6. Governor identity confirmed for this environment.
7. For a testnet or mainnet run: the prior environment's run record (fork
   or testnet respectively) reached [G12](#gate-g12) with every gate PASS —
   including [G6](#gate-g6), which is the evidence that
   `pnpm test:deployment` for the new-contract suites in
   `packages/deployment` ran green against deployed state. N/A for the fork
   rehearsal — it _is_ the first run.

**Pass criterion.** All applicable items hold. Tick the gate; start Stage S1.

**Expected partial state.** `deploy:status` showing every GIP-0088 item
"not started" is the expected pre-deployment picture, not a failure.

**If it fails.** Whatever is missing is a preflight problem, not a runbook
stage: fund the deployer, set the key, review the config. Re-check the gate
once corrected.

---

## Phase A — Contract deployment

<a id="stage-s1"></a>

### Stage S1 — Deploy contracts and implementations

| Field          | Value                                                          |
| -------------- | -------------------------------------------------------------- |
| Phase          | A — Contract deployment                                        |
| Actor          | Deployer (EOA)                                                 |
| Entry gate     | [G1 readiness](#gate-g1)                                       |
| Exit gate      | [G2 contracts-deployed](#gate-g2)                              |
| Parallelizable | No                                                             |
| Reference      | [Gip0088.md — Deploy](Gip0088.md#deploy-gip-0088upgradedeploy) |

`sync` runs automatically as a dependency.

**Steps.**

1. `pnpm hardhat deploy --tags GIP-0088:upgrade,deploy --network <network>`

**Environment notes.** Fork: append `--skip-prompts`. Testnet/mainnet: review
the deployer-balance precheck output before confirming.
<a id="stage-s2"></a>

### Stage S2 — Configure (deployer-scoped)

| Field          | Value                                                                   |
| -------------- | ----------------------------------------------------------------------- |
| Phase          | A — Contract deployment                                                 |
| Actor          | Deployer (EOA)                                                          |
| Entry gate     | [G2 contracts-deployed](#gate-g2)                                       |
| Exit gate      | [G3 deployer-config-done](#gate-g3)                                     |
| Parallelizable | No                                                                      |
| Reference      | [Gip0088.md — Configure](Gip0088.md#configure-gip-0088upgradeconfigure) |

**What this does.** Applies role grants and parameters on the contracts the
deployer governs. Items needing `GOVERNOR_ROLE` on contracts the deployer does
not yet control — or that depend on RM being upgraded — are deferred into the
[S4](#stage-s4) upgrade batch.

**Steps.**

1. `pnpm hardhat deploy --tags GIP-0088:upgrade,configure --network <network>`
   <a id="stage-s3"></a>

### Stage S3 — Transfer governance

| Field          | Value                                                                |
| -------------- | -------------------------------------------------------------------- |
| Phase          | A — Contract deployment                                              |
| Actor          | Deployer (EOA)                                                       |
| Entry gate     | [G3 deployer-config-done](#gate-g3)                                  |
| Exit gate      | [G4 governance-transferred](#gate-g4)                                |
| Parallelizable | No                                                                   |
| Reference      | [Gip0088.md — Transfer](Gip0088.md#transfer-gip-0088upgradetransfer) |

**What this does.** Revokes the deployer's `GOVERNOR_ROLE` on the new contracts
and transfers each ProxyAdmin to the governor. After this stage the deployer has
no special access — all further state changes go through governance.

**Steps.**

1. `pnpm hardhat deploy --tags GIP-0088:upgrade,transfer --network <network>`
   <a id="gate-g2"></a>

### Gate G2 — contracts-deployed

| Field            | Value                 |
| ---------------- | --------------------- |
| Postcondition of | [Stage S1](#stage-s1) |
| Precondition of  | [Stage S2](#stage-s2) |

**Check.** `pnpm hardhat deploy --tags GIP-0088:upgrade --network <network>`

**Pass criterion.** Every new contract and every new implementation shows a
deployed address; no `missing` markers.

**Expected partial state.** Proxies still point at their _old_ implementations —
the upgrade batch is [S4](#stage-s4)/[S5](#stage-s5). Any "not upgraded" / "code
changed" marker at this gate is expected, not a regression.

**If it fails.** Re-run [S1](#stage-s1); the deploy script is idempotent and
resumes from where it stopped.

<a id="gate-g3"></a>

### Gate G3 — deployer-config-done

| Field            | Value                 |
| ---------------- | --------------------- |
| Postcondition of | [Stage S2](#stage-s2) |
| Precondition of  | [Stage S3](#stage-s3) |

**Check.** `pnpm hardhat deploy --tags GIP-0088:upgrade --network <network>` —
the status display is backed by `checkIAConfigured`, `checkRAMConfigured`,
`checkReclaimRoles`, `checkDefaultAllocationConfigured`
([lib/preconditions.ts](../lib/preconditions.ts)).

**Pass criterion.** All deployer-scoped configuration is reported done; the only
items still pending are those explicitly deferred to the upgrade batch.

**Expected partial state.** `checkReclaimRMIntegration` reports "RM not upgraded"
— expected; `RM.setDefaultReclaimAddress` is in the [S4](#stage-s4) batch.

**If it fails.** Re-run [S2](#stage-s2).

<a id="gate-g4"></a>

### Gate G4 — governance-transferred

| Field            | Value                 |
| ---------------- | --------------------- |
| Postcondition of | [Stage S3](#stage-s3) |
| Precondition of  | [Stage S4](#stage-s4) |

**Check.** Status display backed by `checkDeployerRevoked` and
`checkProxyAdminTransferred` ([lib/preconditions.ts](../lib/preconditions.ts)).

**Pass criterion.** The deployer holds no `GOVERNOR_ROLE` on any new contract;
every new-contract ProxyAdmin is owned by the governor.

**If it fails.** Re-run [S3](#stage-s3).

---

## Phase B — Proxy upgrade

<a id="stage-s4"></a>

### Stage S4 — Generate the proxy-upgrade batch

| Field          | Value                                                             |
| -------------- | ----------------------------------------------------------------- |
| Phase          | B — Proxy upgrade                                                 |
| Actor          | Deployer (EOA)                                                    |
| Entry gate     | [G4 governance-transferred](#gate-g4)                             |
| Exit gate      | [G5 upgrade-batch-reviewed](#gate-g5)                             |
| Parallelizable | No                                                                |
| Reference      | [Gip0088.md — Upgrade](Gip0088.md#upgrade-gip-0088upgradeupgrade) |

Builds a single governance TX batch — proxy upgrades for every deployable
proxy with a pending implementation, plus the deferred existing- and
new-contract configuration. Writes a JSON file under `txs/<network>/` (or
`fork/.../txs/` on fork); execution happens at [S5](#stage-s5).

**Steps.**

1. `pnpm hardhat deploy --tags GIP-0088:upgrade,upgrade --network <network>`
   <a id="stage-s5"></a>

### Stage S5 — Sign & execute the proxy-upgrade batch

| Field          | Value                                          |
| -------------- | ---------------------------------------------- |
| Phase          | B — Proxy upgrade                              |
| Actor          | Governor (see [Environments](#environments))   |
| Entry gate     | [G5 upgrade-batch-reviewed](#gate-g5)          |
| Exit gate      | [G6 upgrade-complete](#gate-g6)                |
| Parallelizable | No                                             |
| Reference      | [GovernanceWorkflow.md](GovernanceWorkflow.md) |

Moves every proxy onto its new implementation and applies the deferred
configuration.

**Steps.**

1. Fork / testnet: `pnpm hardhat deploy:execute-governance --network <network>`.
   Mainnet: collect M-of-N signatures on the council Safe and execute.
2. Mainnet only: `pnpm hardhat deploy --tags sync --network <network>` after
   on-chain execution.

**Environment notes.** Execution mechanics differ per environment — see
[Environments](#environments).
<a id="gate-g5"></a>

### Gate G5 — upgrade-batch-reviewed

| Field            | Value                 |
| ---------------- | --------------------- |
| Postcondition of | [Stage S4](#stage-s4) |
| Precondition of  | [Stage S5](#stage-s5) |

**Check.** Upload `txs/<network>/upgrade-*.json` to the Safe Transaction Builder
and decode every transaction. Confirm: exactly one upgrade batch present;
`chainId` matches the network; every proxy upgrade targets the intended
implementation; every deferred-config item (`RC.setPauseGuardian`,
`RM.setDefaultReclaimAddress`, IA/DA/RAM/Reclaim/REO role grants and params)
is expected.

**Pass criterion.** All transactions verified; reviewer sign-off recorded in the
run record.

**If it fails.** Discard the batch, correct config or state, re-run
[S4](#stage-s4).

<a id="gate-g6"></a>

### Gate G6 — upgrade-complete

| Field            | Value                   |
| ---------------- | ----------------------- |
| Postcondition of | [Stage S5](#stage-s5)   |
| Precondition of  | [Stage S5a](#stage-s5a) |

**Check.**

1. `pnpm hardhat deploy --tags GIP-0088:upgrade --network <network>` — shows the
   upgrade phase complete; `isRewardsManagerUpgraded`
   ([lib/contract-checks.ts](../lib/contract-checks.ts)) is true.
2. `pnpm test:deployment` in `packages/horizon` and `packages/subgraph-service`.
3. `TEST_DEPLOYMENT_NETWORK=<network> pnpm test:deployment` in `packages/deployment`
   (the new-contract deployment suites).

**Pass criterion.** Every proxy on its new implementation; all `test:deployment`
suites green; the batch file moved to `txs/<network>/executed/`.

**Expected partial state.** The activation goals (eligibility, issuance) are not
yet done — `deploy --tags GIP-0088` will show Phase C items pending. Expected.

**If it fails.** A failed proxy upgrade is not auto-recoverable — triage against
the batch and `GovernanceWorkflow.md` before re-running any stage.

---

## Phase C — Activation

Each activation goal is generate → review gate → execute → state gate. Gates
here verify _wiring_; behavioral correctness comes from [G15](#gate-g15).
Eligibility-integrate ([S6](#stage-s6)/[S7](#stage-s7)) is a no-op only when
`RM.providerEligibilityOracle` already matches the configured oracle; if it
differs, the stage re-points it (config is the source of truth).

**DIPs-dormant rollout.** This environment ships with on-chain indexing
agreements (DIPs) **off**, via two independent levers — neither turned on by the
activation goals:

- **Protocol-funded path** — `IssuanceAllocator.allocations` in
  `config/<network>.json5` omits `RecurringAgreementManager`, so RAM receives 0
  issuance. `issuance-connect` puts RM at 100%, so `issuance-allocate`
  ([S10](#stage-s10)/[S11](#stage-s11)) is a no-op — run it only to confirm.
- **Payer-funded path** — `RecurringCollector` is paused ([S5a](#stage-s5a)).
  This is a **pause-guardian** action managed out-of-band, not by the deploy
  package; `09_end` does **not** verify it, so [G6a](#gate-g6a) is the gate that
  does.

Turning DIPs on later is the inverse of both levers — see
[Activating DIPs later](#activating-dips-later).

<a id="stage-s5a"></a>

### Stage S5a — Pause RecurringCollector (DIPs dormant)

| Field          | Value                                            |
| -------------- | ------------------------------------------------ |
| Phase          | C — Activation                                   |
| Actor          | Pause guardian (out-of-band; see below)          |
| Entry gate     | [G6 upgrade-complete](#gate-g6)                  |
| Exit gate      | [G6a dips-dormant](#gate-g6a)                    |
| Parallelizable | No                                               |
| Reference      | `RecurringCollector.pause()` — onlyPauseGuardian |

**What this does.** Pauses `RecurringCollector` so no indexing agreement can be
accepted, collected, updated, or cancelled (`accept`/`collect`/`update`/`cancel`
are all `whenNotPaused`). This closes the payer-funded DIP path; the
protocol-funded path is already off via config (RAM unallocated).

**Why out-of-band.** `RC.pause()` is `onlyPauseGuardian`, and the pause guardian
(`Controller.pauseGuardian()`) is a distinct actor from the protocol governor by
design — a separate Safe on mainnet (`0xB0aD…3aAE`), a separate EOA on testnet
(`0xa044…20D7`). The deploy package only emits governor batches, so it neither
sets nor clears pause state; the guardian performs this directly.

**When.** As soon as [G6](#gate-g6) lands — the guardian role is granted in the
[S4](#stage-s4) upgrade batch, so the guardian can act the moment the upgrade
executes. RC is unpaused by default (its initializer leaves it live), so pause
promptly to minimise the window.

**Steps.**

1. Guardian executes `RecurringCollector.pause()`:
   - Mainnet: propose & execute on the pause-guardian Safe (`0xB0aD…3aAE`).
   - Testnet: `cast send <RC> "pause()" --from <guardian>` with the guardian EOA
     key (`0xa044…20D7`); the governor key cannot do this.

<a id="stage-s6"></a>

### Stage S6 — Generate the eligibility-integrate batch

| Field          | Value                                                        |
| -------------- | ------------------------------------------------------------ |
| Phase          | C — Activation                                               |
| Actor          | Deployer (EOA)                                               |
| Entry gate     | [G6a dips-dormant](#gate-g6a)                                |
| Exit gate      | [G7 eligibility-batch-reviewed](#gate-g7)                    |
| Parallelizable | No                                                           |
| Reference      | [Gip0088.md — Activation goals](Gip0088.md#activation-goals) |

**What this does.** Generates the batch wiring each target's eligibility oracle:
`RM.setProviderEligibilityOracle(...)` and `RAM.setProviderEligibilityOracle(...)`,
each taken from config (`RewardsManager.eligibilityOracle` /
`RecurringAgreementManager.eligibilityOracle` in `config/<network>.json5` — a full
oracle contract name; a target whose field is omitted is left unwired).

**Steps.**

1. `pnpm hardhat deploy --tags GIP-0088:eligibility-integrate --network <network>`

**Environment notes.** Per target, no batch entry when that target's oracle
already matches config; a target whose oracle differs is re-pointed to the
configured one (overriding the prior value). If every configured target already
matches, record [G7](#gate-g7)/[G8](#gate-g8) as done-with-reason and proceed to
[S8](#stage-s8).
<a id="stage-s7"></a>

### Stage S7 — Sign & execute the eligibility-integrate batch

| Field          | Value                                          |
| -------------- | ---------------------------------------------- |
| Phase          | C — Activation                                 |
| Actor          | Governor (see [Environments](#environments))   |
| Entry gate     | [G7 eligibility-batch-reviewed](#gate-g7)      |
| Exit gate      | [G8 eligibility-active](#gate-g8)              |
| Parallelizable | No                                             |
| Reference      | [GovernanceWorkflow.md](GovernanceWorkflow.md) |

**Steps.**

1. `pnpm hardhat deploy:execute-governance --network <network>` (fork/testnet) or
   council Safe execution (mainnet).
   <a id="stage-s8"></a>

### Stage S8 — Generate the issuance-connect batch

| Field          | Value                                                        |
| -------------- | ------------------------------------------------------------ |
| Phase          | C — Activation                                               |
| Actor          | Deployer (EOA)                                               |
| Entry gate     | [G8 eligibility-active](#gate-g8)                            |
| Exit gate      | [G9 connect-batch-reviewed](#gate-g9)                        |
| Parallelizable | No                                                           |
| Reference      | [Gip0088.md — Activation goals](Gip0088.md#activation-goals) |

**What this does.** Generates the batch wiring the Issuance Allocator to the
RewardsManager: `GraphToken.addMinter(IA)` → `RM.setIssuanceAllocator(IA)` →
`IA.setTargetAllocation(RM, 0, rate)` → `IA.setDefaultTarget(DA)`. Ordering is
load-bearing. The script **exits** if the IA rate ≠ RM rate invariant fails.

**Steps.**

1. `pnpm hardhat deploy --tags GIP-0088:issuance-connect --network <network>`
   <a id="stage-s9"></a>

### Stage S9 — Sign & execute the issuance-connect batch

| Field          | Value                                          |
| -------------- | ---------------------------------------------- |
| Phase          | C — Activation                                 |
| Actor          | Governor (see [Environments](#environments))   |
| Entry gate     | [G9 connect-batch-reviewed](#gate-g9)          |
| Exit gate      | [G10 issuance-connected](#gate-g10)            |
| Parallelizable | No                                             |
| Reference      | [GovernanceWorkflow.md](GovernanceWorkflow.md) |

**Steps.**

1. `pnpm hardhat deploy:execute-governance --network <network>` (fork/testnet) or
   council Safe execution (mainnet).
   <a id="stage-s10"></a>

### Stage S10 — Generate the issuance-allocate batch

| Field          | Value                                                        |
| -------------- | ------------------------------------------------------------ |
| Phase          | C — Activation                                               |
| Actor          | Deployer (EOA)                                               |
| Entry gate     | [G10 issuance-connected](#gate-g10)                          |
| Exit gate      | [G11 allocate-batch-reviewed](#gate-g11)                     |
| Parallelizable | No                                                           |
| Reference      | [Gip0088.md — Activation goals](Gip0088.md#activation-goals) |

**What this does.** Generates `IA.setTargetAllocation(target, ...)` for each
target in config `IssuanceAllocator.allocations`, set to exactly its configured
rate (no rebalancing). **Exits** unless the config `issuancePerBlock` equals RM's
on-chain rate and the per-target rates sum to it. Skips when no allocations are
configured.

In the **DIPs-dormant** config the only target is RM, already at 100% from
[S8](#stage-s8) `issuance-connect`, so this stage emits **no transactions** —
run it to confirm the table matches on-chain. (When DIPs are later activated, the
RAM allocation is added back to config and this stage does the real work.)

**Steps.**

1. `pnpm hardhat deploy --tags GIP-0088:issuance-allocate --network <network>`
   <a id="stage-s11"></a>

### Stage S11 — Sign & execute the issuance-allocate batch

| Field          | Value                                          |
| -------------- | ---------------------------------------------- |
| Phase          | C — Activation                                 |
| Actor          | Governor (see [Environments](#environments))   |
| Entry gate     | [G11 allocate-batch-reviewed](#gate-g11)       |
| Exit gate      | [G12 rollout-complete](#gate-g12)              |
| Parallelizable | No                                             |
| Reference      | [GovernanceWorkflow.md](GovernanceWorkflow.md) |

**Steps.**

1. `pnpm hardhat deploy:execute-governance --network <network>` (fork/testnet) or
   council Safe execution (mainnet).
   <a id="gate-g6a"></a>

### Gate G6a — dips-dormant

| Field            | Value                   |
| ---------------- | ----------------------- |
| Postcondition of | [Stage S5a](#stage-s5a) |
| Precondition of  | [Stage S6](#stage-s6)   |

**Check.** `cast call <RecurringCollector> "paused()(bool)" --rpc-url <rpc>` (or
the equivalent read). Confirm `true`.

**Pass criterion.** `RC.paused() == true`. With RAM unallocated (config) and RC
paused, neither DIP funding path can create or collect an agreement.

**Note.** `09_end` (the [G12](#gate-g12) assertion) does **not** check pause
state — it would report GIP-0088 "complete" with RC still live. This gate is the
only check that the payer-funded path is closed; do not skip it.

**If it fails.** RC is still live — re-run [S5a](#stage-s5a) (have the guardian
execute `pause()`). Until this gate passes the rollout is not dormant.

<a id="gate-g7"></a>

### Gate G7 — eligibility-batch-reviewed

| Field            | Value                 |
| ---------------- | --------------------- |
| Postcondition of | [Stage S6](#stage-s6) |
| Precondition of  | [Stage S7](#stage-s7) |

**Check.** Decode the `eligibility-integrate` batch in the Safe Transaction
Builder: one `setProviderEligibilityOracle(...)` per configured target (RM
and/or RAM), each call's argument matching the address of the oracle contract
named in that target's config (`<target>.eligibilityOracle`).

**Pass criterion.** Verified; sign-off recorded. **Or:** empty batch because
every configured target's oracle already matches config — record done-with-reason.

**If it fails.** Discard, correct, re-run [S6](#stage-s6).

<a id="gate-g8"></a>

### Gate G8 — eligibility-active

| Field            | Value                 |
| ---------------- | --------------------- |
| Postcondition of | [Stage S7](#stage-s7) |
| Precondition of  | [Stage S8](#stage-s8) |

**Check.** `pnpm hardhat deploy --tags GIP-0088 --network <network>` — the
eligibility phase reads each target's `getProviderEligibilityOracle()` back as
the oracle named in its config (or unset for a target whose config omits one).

**Pass criterion.** Each target's oracle matches its config; batches executed. On
an environment where an oracle was pre-set, mark N/A with reason.

**If it fails.** Re-run [S7](#stage-s7).

<a id="gate-g9"></a>

### Gate G9 — connect-batch-reviewed

| Field            | Value                 |
| ---------------- | --------------------- |
| Postcondition of | [Stage S8](#stage-s8) |
| Precondition of  | [Stage S9](#stage-s9) |

**Check.** Decode the `issuance-connect` batch. Confirm the four transactions and
their **order**: `addMinter` → `setIssuanceAllocator` → `setTargetAllocation(RM)`
→ `setDefaultTarget`. Confirm the RM rate argument.

**Pass criterion.** Order and arguments verified; sign-off recorded.

**If it fails.** Discard, correct, re-run [S8](#stage-s8).

<a id="gate-g10"></a>

### Gate G10 — issuance-connected

| Field            | Value                   |
| ---------------- | ----------------------- |
| Postcondition of | [Stage S9](#stage-s9)   |
| Precondition of  | [Stage S10](#stage-s10) |

**Check.** `checkIssuanceConnectComplete` ([lib/contract-checks.ts](../lib/contract-checks.ts)),
exercised by `pnpm hardhat deploy --tags GIP-0088,all --network <network>`.

**Pass criterion.** IA integrated, IA is a GraphToken minter, IA/RM rates
aligned, RM is a 100% self-minting target, total allocation equals issuance.

**If it fails.** Re-run [S9](#stage-s9).

<a id="gate-g11"></a>

### Gate G11 — allocate-batch-reviewed

| Field            | Value                   |
| ---------------- | ----------------------- |
| Postcondition of | [Stage S10](#stage-s10) |
| Precondition of  | [Stage S11](#stage-s11) |

**Check.** Decode the `issuance-allocate` batch. Confirm one
`IA.setTargetAllocation(target, ...)` per configured target and that the rates
equal those in `config/<network>.json5` (the batch generation already verified
the table sums to RM's `issuancePerBlock`). After execution, inspect the live per-target
allocation with `pnpm hardhat ia:status --network <network>` — it prints each
target's allocator/self rates and an explicit RAM call-out (`deploy:status`
only reports the aggregate "100% allocated", which hides a missing RAM line
when RM self-minting covers the slack).

**Pass criterion.** Rates verified; sign-off recorded.

**If it fails.** Discard, correct, re-run [S10](#stage-s10).

<a id="gate-g12"></a>

### Gate G12 — rollout-complete

| Field            | Value                   |
| ---------------- | ----------------------- |
| Postcondition of | [Stage S11](#stage-s11) |
| Precondition of  | [Stage S12](#stage-s12) |

**Check.** `pnpm hardhat deploy --tags GIP-0088,all --network <network>` — the
`09_end` assertion script; exits non-zero on any unmet goal.

**Pass criterion.** Exit 0 — upgrade, issuance-connect and eligibility-integrate
all verified; the configured REO is the active oracle; and both
`revertOnIneligible` and the allocation rates match config (RAM unallocated in
the dormant config). Note: `09_end` does **not** check `RC.paused()` — dormancy
of the payer-funded path is attested by [G6a](#gate-g6a), not here, so both gates
must pass for the rollout to be dormant.

**If it fails.** Re-run the stage that owns the unmet goal as named in the
output.

---

## Phase D — Off-chain rollout & close-out

Skipped on the fork rehearsal. Stages may begin once contract addresses are
known (after [G2](#gate-g2)).

<a id="stage-s12"></a>

### Stage S12 — Publish address book & bump shared packages

| Field          | Value                                                               |
| -------------- | ------------------------------------------------------------------- |
| Phase          | D — Off-chain rollout & close-out                                   |
| Actor          | Engineering team                                                    |
| Entry gate     | [G12 rollout-complete](#gate-g12)                                   |
| Exit gate      | [G13 packages-published](#gate-g13)                                 |
| Parallelizable | From [G2](#gate-g2) — address-book PR can open once addresses exist |
| Reference      | [address-book/README.md](address-book/README.md)                    |

**What this does.** Publishes the new address book to npm and bumps the
`interfaces` / `toolshed` consumers.

**Steps.**

1. Open the address-book PR; merge once contracts are live.
2. Publish the address book; bump dependent packages.
   <a id="stage-s13"></a>

### Stage S13 — Release off-chain components

| Field          | Value                                                    |
| -------------- | -------------------------------------------------------- |
| Phase          | D — Off-chain rollout & close-out                        |
| Actor          | Component owners                                         |
| Entry gate     | [G13 packages-published](#gate-g13)                      |
| Exit gate      | [G14 offchain-released](#gate-g14)                       |
| Parallelizable | From [G12](#gate-g12) — components pin to live addresses |
| Reference      | each component repo                                      |

**What this does.** Releases the off-chain stack pinned to the new contracts.

**Steps (one line per component — detail lives in each repo).**

1. indexing-payments-subgraph
2. dipper
3. IISA (subgraph-dips-indexer-selection)
4. indexer-agent
5. indexer-service-rs
6. gateway
7. monitoring / EON
   <a id="stage-s14"></a>

### Stage S14 — Run manual testnet test plans

| Field          | Value                                                      |
| -------------- | ---------------------------------------------------------- |
| Phase          | D — Off-chain rollout & close-out                          |
| Actor          | Test owners                                                |
| Entry gate     | [G14 offchain-released](#gate-g14)                         |
| Exit gate      | [G15 test-plans-passed](#gate-g15)                         |
| Parallelizable | No                                                         |
| Reference      | [reo/README.md](../../issuance/docs/testing/reo/README.md) |

**What this does.** Executes the manual test plans that provide behavioral
coverage of the new contracts and the integrated stack.

**Steps.**

1. [BaselineTestPlan](../../issuance/docs/testing/reo/BaselineTestPlan.md) — run first.
2. [ReoTestPlan](../../issuance/docs/testing/reo/ReoTestPlan.md)
3. [RewardsConditionsTestPlan](../../issuance/docs/testing/reo/RewardsConditionsTestPlan.md)
4. [SubgraphDenialTestPlan](../../issuance/docs/testing/reo/SubgraphDenialTestPlan.md)
5. Issuance Allocator test plan (referenced from the same directory once
   authored).

**Environment notes.** Testnet only. N/A on fork (no off-chain components,
no real indexers — see the Phase D opener) and N/A on mainnet (the testnet
run carries the behavioral evidence). On mainnet, mark [G15](#gate-g15) N/A
with that reason.
<a id="stage-s15"></a>

### Stage S15 — Comms, security & indexer upgrade window

| Field          | Value                              |
| -------------- | ---------------------------------- |
| Phase          | D — Off-chain rollout & close-out  |
| Actor          | Coordinator                        |
| Entry gate     | [G15 test-plans-passed](#gate-g15) |
| Exit gate      | [G16 go-live-complete](#gate-g16)  |
| Parallelizable | No                                 |

**Steps.**

1. Add the new contracts to Immunefi.
2. Configure monitoring alerts for the new contracts.
3. Publish announcements.
4. Open the 3-week indexer upgrade window.
   <a id="gate-g13"></a>

### Gate G13 — packages-published

| Field            | Value                   |
| ---------------- | ----------------------- |
| Postcondition of | [Stage S12](#stage-s12) |
| Precondition of  | [Stage S13](#stage-s13) |

**Check.** The address book is published to npm at the new version; dependent
packages are bumped.

**Pass criterion.** Registry shows the new versions; the address-book PR is merged.

**If it fails.** Re-run [S12](#stage-s12).

<a id="gate-g14"></a>

### Gate G14 — offchain-released

| Field            | Value                   |
| ---------------- | ----------------------- |
| Postcondition of | [Stage S13](#stage-s13) |
| Precondition of  | [Stage S14](#stage-s14) |

**Check.** Each component in [S13](#stage-s13) is running its new version pinned
to the GIP-0088 addresses — per-component release checklist.

**Pass criterion.** All seven components released and confirmed live.

**If it fails.** Re-run the affected component release in [S13](#stage-s13).

<a id="gate-g15"></a>

### Gate G15 — test-plans-passed

| Field            | Value                   |
| ---------------- | ----------------------- |
| Postcondition of | [Stage S14](#stage-s14) |
| Precondition of  | [Stage S15](#stage-s15) |

**Check.** Every test plan in [S14](#stage-s14) executed; results linked in the
run record; failures triaged.

**Pass criterion.** All plans passed, or every failure has a recorded
non-regression diagnosis. This is the **behavioral** gate for the new contracts
(IA, REO, RAM) — it cannot be skipped on testnet. On mainnet it is N/A with a
recorded reason (the testnet run carries the behavioral evidence).

**If it fails.** A genuine regression blocks [S15](#stage-s15); fix and re-run
the affected plan.

<a id="gate-g16"></a>

### Gate G16 — go-live-complete

| Field            | Value                   |
| ---------------- | ----------------------- |
| Postcondition of | [Stage S15](#stage-s15) |
| Precondition of  | — (end)                 |

**Check.** Immunefi updated; alerts live; announcements posted; indexer upgrade
window opened.

**Pass criterion.** All four done. The run is complete — mark the run record
`done`.

**If it fails.** Re-run the outstanding item in [S15](#stage-s15).

---

## Running this runbook

Each run is recorded under [gip0088/runs/](gip0088/runs/) from
[gip0088/runs/Template.md](gip0088/runs/Template.md) — named
`<date>-<environment>.md`. The run file records human/process facts (who
signed, when, tx hashes, waivers); live protocol state comes from
`pnpm hardhat deploy --tags GIP-0088 --network <network>`.

## Recovery

Deploy scripts are idempotent; most gate failures recover by re-running the
prior stage. Abort is clean before [G4](#gate-g4); after, recovery needs a
follow-up governance batch — see
[GovernanceWorkflow.md](GovernanceWorkflow.md).

## Sequenced bundle generation (single council signing session)

The default flow generates each governance bundle only _after_ the previous one
executes on-chain — every activation goal reads live state and gates on the RM
upgrade ([S6](#stage-s6)/[S8](#stage-s8) skip or exit until RM is upgraded). On
mainnet, where the council signs M-of-N over days, that forces one signing round
per stage. To hand the council **every** GIP-0088 bundle at once, set
`GIP_0088_ASSUME_UPGRADED=1` when generating the activation bundles:

```bash
# Upgrade bundle — generated normally (already carries the RM-gated config:
# setDefaultReclaimAddress + setRevertOnIneligible, ordered after the RM upgrade)
pnpm hardhat deploy --tags GIP-0088:upgrade,upgrade --network arbitrumOne

# Activation bundles — generated ahead of the upgrade executing
GIP_0088_ASSUME_UPGRADED=1 pnpm hardhat deploy --tags GIP-0088:eligibility-integrate --network arbitrumOne
GIP_0088_ASSUME_UPGRADED=1 pnpm hardhat deploy --tags GIP-0088:issuance-connect     --network arbitrumOne
```

With the flag, `eligibility-integrate` and `issuance-connect` skip the
"is RM upgraded on-chain" guard and the post-upgrade idempotency reads (which
would revert against the old implementation) and emit their full tx set.

**Execution — nonce order is load-bearing.** These activation bundles are
**sequenced-only**: valid only when executed _after_ the upgrade bundle. Queue
them on the council Safe in order:

| Safe nonce | Bundle                                          |
| ---------- | ----------------------------------------------- |
| N          | `gip-0088-upgrades.json` (upgrades + RM config) |
| N+1        | `eligibility-integrate` bundle                  |
| N+2        | `gip-0088-issuance-connect.json`                |

The Safe executes in strict nonce order, so RM is upgraded by the time N+1/N+2
run, and the council reviews + signs all three in one session. If bundle N fails,
N+1/N+2 are blocked rather than executing against an un-upgraded RM.

- **Kept:** the `issuance-connect` rate invariant
  (`IA.issuancePerBlock == RM.issuancePerBlock`) is still enforced — it reads
  `RM.issuancePerBlock`, which exists on the un-upgraded RM.
- **Dropped:** idempotency. The flag blind-emits the full set, so use it only for
  the initial sequenced generation — **not** for re-runs or recovery, where the
  default (guarded) mode reads live state and emits only the remaining work.
- **`issuance-allocate`** stays a no-op in the DIPs-dormant config (RM already
  100% from `issuance-connect`), so it needs no bundle. On a DIPs-active config,
  generate it too, with the flag, as an `N+3` sequenced bundle.

This mode trades the staged per-goal review gates ([G7](#gate-g7)/[G9](#gate-g9))
for a single up-front review of all bundles — a deliberate choice for the
one-session council workflow, not the default.

## Activating DIPs later

DIPs ship dormant (see [Phase C](#phase-c--activation)). Turning them on is the
inverse of the two dormancy levers, and is a **separate, later** change — not
part of this rollout:

1. **Restore the issuance split** — in `config/<network>.json5`, add the
   `RecurringAgreementManager` allocation back to `IssuanceAllocator.allocations`
   (e.g. mainnet `RewardsManager: 114.73` + `RecurringAgreementManager: 6`), then
   run `GIP-0088:issuance-allocate` and execute the governor batch. `ia:status`
   should then show RAM funded. The decrease-first ordering means RM drops and RAM
   rises within one batch.
2. **Unpause the collector** — the pause guardian executes
   `RecurringCollector.unpause()` (mainnet: guardian Safe `0xB0aD…3aAE`; testnet:
   guardian EOA `0xa044…20D7`). The governor cannot do this.

Each lever is independently reversible: re-apply the RM-only config + re-run
`issuance-allocate` to de-fund RAM, and have the guardian `RC.pause()` again.

## See also

- [Gip0088.md](Gip0088.md) — reference guide: scripts, tags, preconditions, model
- [GovernanceWorkflow.md](GovernanceWorkflow.md) — governance TX generation and execution
- [LocalForkTesting.md](LocalForkTesting.md) — fork rehearsal setup
- [DeploymentSetup.md](DeploymentSetup.md) — environment and account configuration
- [deploy/ImplementationPrinciples.md](deploy/ImplementationPrinciples.md) — deploy-script patterns
