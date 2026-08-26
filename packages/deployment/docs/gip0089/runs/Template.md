# GIP-0089 Run — &lt;environment&gt;

Per-run record. Copy this file to `<date>-<environment>.md`, fill the header,
and tick stages/gates as the run progresses. The structure mirrors
[Gip0089Runbook.md](../../Gip0089Runbook.md) — see it for what each stage and
gate means. This file holds the human/process facts (who, when, tx hashes,
waivers); live protocol state is re-derivable with
`pnpm hardhat deploy --tags GIP-0089 --network <network>`.

## Run metadata

| Field            | Value                                                        |
| ---------------- | ------------------------------------------------------------ |
| Environment      | fork \| testnet \| mainnet                                   |
| Network          | localhost \| arbitrumSepolia \| arbitrumOne                  |
| Deployer         | 0x…                                                          |
| Governor         | 0x… (EOA \| Safe)                                            |
| Runbook revision | Gip0089Runbook.md @ &lt;commit-sha&gt;                       |
| Prior run record | &lt;path to the prior environment's run, or N/A for fork&gt; |
| Started          | YYYY-MM-DD                                                   |
| Status           | in progress \| done \| aborted                               |

## Progress

Mark each stage `[x]` when its work is complete; mark each gate `[x]` only when
its pass criterion is met. A gate that is waived or N/A is still ticked — record
the reason in the Waivers section.

### Entry

- [ ] **G1** readiness — PASS date / by:

### Phase A — Contract deployment

- [ ] **S1** Deploy & configure — date / by:
- [ ] **G2** roles-correct — governor GOVERNOR_ROLE, pause guardian PAUSE_ROLE,
      InnovationOperator OPERATOR_ROLE. **Must pass before S2** — S2 revokes the deployer,
      after which a missed role needs governance. — PASS date / by:
- [ ] **S2** Transfer governance — date / by:
- [ ] **G3** governance-transferred — ProxyAdmin at governor, GOVERNOR_ROLE governor-only
      — PASS date / by:

### Phase B — Allocation

- [ ] **S3** Generate the allocation batch — date / by:
      batch file:
- [ ] **G4** batch-reviewed — Tenderly simulation: two calls, RewardsManager first, both
      succeed, resulting state matches config — PASS date / reviewer:
      simulation link:
- [ ] **S4** Sign & execute — date / by:
      tx hash(es):
- [ ] **G5** allocated — `GIP-0089,all` passes; bare `GIP-0088` still passes; `ia:status`
      shows the split fully allocated — PASS date / by:

### Phase C — Close-out

- [ ] **S5** Publish address book & bump packages — date / by:
- [ ] **S6** Immunefi, alerts, announcements — date / by:
- [ ] **G6** complete — PASS date / by:

## Waivers & N/A gates

Record every gate marked done without meeting its full pass criterion — and why.

| Gate | Waived / N/A | Reason |
| ---- | ------------ | ------ |
|      |              |        |

## Notes & deviations

-
