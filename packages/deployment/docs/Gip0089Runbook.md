# GIP-0089 Rollout Runbook

Handoff protocol for the GIP-0089 innovation allocation rollout: who does what, in what
order, and what a human must judge before it is safe to continue.

What each script does, what it guards, and why is in [Gip0089.md](Gip0089.md) — not
repeated here. Anything a machine can check is a script guard or a test, not a checkbox;
this document covers only the parts that need a person.

Run once per environment, fork first. Record each run under
[gip0089/runs/](gip0089/runs/) from [its template](gip0089/runs/Template.md).

## Environments

| Environment    | `<network>`       | How S3 gets signed                                    | Pace    |
| -------------- | ----------------- | ----------------------------------------------------- | ------- |
| Fork rehearsal | `localhost`       | `deploy:execute-governance` impersonates the governor | instant |
| Testnet        | `arbitrumSepolia` | `deploy:execute-governance` signs with the EOA key    | minutes |
| Mainnet        | `arbitrumOne`     | Batch uploaded to the council Safe, signed M-of-N     | days    |

`--skip-prompts` is required on testnet and mainnet; rocketh otherwise prompts for
gas-price confirmation before every mutating call. See
[GovernanceWorkflow.md](GovernanceWorkflow.md) for the per-environment detail.

<a id="gate-g1"></a>

## G1 — Readiness

Confirm before starting. Items a script already enforces are noted as such; they are
listed so a failure here is understood, not so you re-derive them.

- [ ] Tree is at the intended deployment commit — record the sha in the run record.
- [ ] `pnpm test` is green in `packages/deployment`. This includes the shared-implementation
      drift guard; if it fails, stop and make a recorded decision (upgrade all three
      DirectAllocation proxies together, or pin the implementation).
- [ ] `config/<network>.json5` reviewed: the split matches the GIP and sums to the
      unchanged `issuancePerBlock` anchor. **Human judgment — the scripts verify the sum,
      not that the numbers are the ones governance approved.**
- [ ] Mainnet only: `0x7700d56D2cFAFa620048633B2586b063eCD93dd1` confirmed as a deployed
      Safe. It will hold `OPERATOR_ROLE` and be able to call `sendTokens`.
- [ ] Deployer funded, key accessible, governor identity confirmed for this environment.
- [ ] Prior environment's run record reached the end with every gate passed. N/A on fork.

_Enforced in code, listed for diagnosis:_ `InnovationOperator` present in the address book
(S1 configure bails without it); GIP-0088 `issuance-connect` complete on this network
(S2 refuses to build a batch without it — fix with
`pnpm hardhat deploy --tags GIP-0088:issuance-connect --network <network>`).

## The run

| #   | Stage                               | Actor              | Command                                                                    |
| --- | ----------------------------------- | ------------------ | -------------------------------------------------------------------------- |
| S1  | Deploy & configure                  | Deployer           | `pnpm hardhat deploy --tags InnovationAllocation,deploy` then `,configure` |
| S2  | Transfer governance                 | Deployer           | `pnpm hardhat deploy --tags InnovationAllocation,transfer`                 |
| S3  | Generate the allocation batch       | Deployer           | `pnpm hardhat deploy --tags GIP-0089:allocate`                             |
| S4  | Sign & execute                      | Governor / Council | `pnpm hardhat deploy:execute-governance`, or the Safe                      |
| S5  | Publish address book, bump packages | Engineering        | see [address-book/README.md](address-book/README.md)                       |
| S6  | Immunefi, alerts, announcements     | Coordinator        | —                                                                          |

All commands take `--network <network>`. Every stage is idempotent — re-running one is a
no-op. S5 can start as soon as the address exists (after S1).

**S2 is the irreversible boundary.** It revokes the deployer's `GOVERNOR_ROLE` and hands
the ProxyAdmin to the governor. Everything before it is recoverable by re-running a stage;
after it, any correction needs a governance batch. That is why [G2](#gate-g2) sits between
S1 and S2 rather than after both — an incomplete configure must be caught before the
deployer loses access.

Two code guards back the gate up, so the boundary holds even if G2 is skipped:
`04_configure` grants `GOVERNOR_ROLE` and `PAUSE_ROLE` even when `InnovationOperator` is
missing from the address book (only the `OPERATOR_ROLE` grant is skipped, with a `❌`), and
`05_transfer_governance` refuses to revoke the deployer while the governor does not hold
`GOVERNOR_ROLE`. Neither replaces G2 — a contract with no operator still needs fixing
before S2 — but neither leaves it unrecoverable.

<a id="gate-g2"></a>

## G2 — Roles correct

_After S1, **before S2**. The pre-transfer checkpoint — the last point where the deployer
can still fix a role itself._

```
pnpm hardhat deploy --tags InnovationAllocation --network <network>
```

Read-only. Required: `GOVERNOR_ROLE` on the governor, `PAUSE_ROLE` on the pause guardian,
`OPERATOR_ROLE` on exactly the `InnovationOperator`. At this point the deployer still holds
`GOVERNOR_ROLE` too, so the exclusivity row reads ✗ "too many holders (2)" — that is
expected here and clears at [G3](#gate-g3). The two `verified` rows stay ✗ on a fork.

Before S1 this command reporting "not deployed" is the expected picture, not a failure.

Fails: re-run `,configure`. If `OPERATOR_ROLE` is unassigned, check `InnovationOperator` is
in the address book — configure returns quietly without it. **Do not run S2 until this
passes.** Abort is clean up to this point.

<a id="gate-g3"></a>

## G3 — Governance transferred

_After S2, before S3._ Same command. Now required: ProxyAdmin owned by the governor, and
`GOVERNOR_ROLE` held **only** by the governor — the deployer is out.

Fails: re-run `,transfer`; it is idempotent and resumes.

<a id="gate-g4"></a>

## G4 — Batch reviewed

_After S3, before S4._ **This is the gate that needs a person.** Everything downstream is
machine-checked; this is the last point where judgment beats tooling, and the first point
where a mistake costs real GRT.

**Simulate `gip-0089-innovation-allocation` in Tenderly** — as a Safe batch, against the
target network. Simulation beats reading the batch: it decodes the calls against the
verified ABI, executes them in order, and shows the resulting state. The batch itself
carries raw calldata (`contractMethod` is null on every transaction this repo emits), so
reading the JSON alone gives you hex.

Confirm in the simulation:

1. **Exactly two** `setTargetAllocation` calls, and nothing else.
2. **`RewardsManager` first**, `InnovationAllocation` second. The helper sorts
   decrease-first automatically. Reversed, the second call reverts
   `InsufficientAllocationAvailable` — which the simulation surfaces rather than leaving
   you to reason about.
3. Both calls succeed.
4. The resulting state: `RewardsManager` self-mint and `InnovationAllocation`
   allocator-mint at the `config/<network>.json5` rates, summing to the unchanged
   `issuancePerBlock`.

Record the reviewer, the simulation link, and sign-off in the run record.

Fails: discard the batch, fix config or state, re-run S3.

<a id="gate-g5"></a>

## G5 — Allocated

_After S4, before S5._

```
pnpm hardhat deploy --tags GIP-0089,all --network <network>   # exits non-zero on any unmet goal
pnpm hardhat deploy --tags GIP-0088     --network <network>   # total issuance unchanged
pnpm hardhat ia:status                  --network <network>   # 80/20, fully allocated
```

⚠️ `GIP-0089,all` is **write-capable** — `all` activates every action verb on its
dependency chain. Run it only after S4, when each step is already a no-op. For a read-only
view use `--tags GIP-0089`. Note the second command is bare `GIP-0088`, _not_ `GIP-0088,all`,
which would stage an unrelated RewardsManager upgrade batch.

If `GIP-0088` fails here, total issuance moved — out of scope for this GIP. Stop and
resolve before close-out.

<a id="gate-g6"></a>

## G6 — Complete

_After S6._ Address book published and dependents bumped; `InnovationAllocation` added to
Immunefi; monitoring alerts live; announcements posted. Mark the run record `done`.

## Recovery

Deploy scripts are idempotent, so most failures recover by re-running the prior stage.
Abort is clean before S2. After S2, corrections need governance; after S4, so does the allocation — see
[GovernanceWorkflow.md](GovernanceWorkflow.md).

GIP-0089 ships no off-chain component and no keeper: `distributeIssuance()` is
permissionless, and every `setTargetAllocation` triggers a distribution.

## See also

- [Gip0089.md](Gip0089.md) — scripts, tags, preconditions, role model
- [deploy/InnovationAllocationDeployment.md](deploy/InnovationAllocationDeployment.md) — component doc
- [Gip0088Runbook.md](Gip0088Runbook.md) — prior rollout, same model
- [LocalForkTesting.md](LocalForkTesting.md) · [DeploymentSetup.md](DeploymentSetup.md)
