# GIP-0088 Run — &lt;environment&gt;

Per-run record. Copy this file to `<date>-<environment>.md`, fill the header,
and tick stages/gates as the run progresses. The structure mirrors
[Gip0088Runbook.md](../../Gip0088Runbook.md) — see it for what each stage and
gate means. This file holds the human/process facts (who, when, tx hashes,
waivers); live protocol state is re-derivable with
`pnpm hardhat deploy --tags GIP-0088 --network <network>`.

## Run metadata

| Field            | Value                                                        |
| ---------------- | ------------------------------------------------------------ |
| Environment      | fork \| testnet \| mainnet                                   |
| Network          | localhost \| arbitrumSepolia \| arbitrumOne                  |
| Deployer         | 0x…                                                          |
| Governor         | 0x… (EOA \| Safe)                                            |
| Runbook revision | Gip0088Runbook.md @ &lt;commit-sha&gt;                       |
| Prior run record | &lt;path to the prior environment's run, or N/A for fork&gt; |
| Started          | YYYY-MM-DD                                                   |
| Status           | in progress \| done \| aborted                               |

## Progress

Mark each stage `[x]` when its work is complete; mark each gate `[x]` only when
its pass criterion is met. A gate that is waived or N/A is still ticked — record
the reason in the Waivers section.

### Entry — Readiness

- [ ] **G1** readiness — PASS date / by:

### Phase A — Contract deployment

- [ ] **S1** Deploy contracts and implementations — date / by:
- [ ] **G2** contracts-deployed — PASS date / by:
- [ ] **S2** Configure (deployer-scoped) — date / by:
- [ ] **G3** deployer-config-done — PASS date / by:
- [ ] **S3** Transfer governance — date / by:
- [ ] **G4** governance-transferred — PASS date / by:

### Phase B — Proxy upgrade

- [ ] **S4** Generate the proxy-upgrade batch — date / by:
      batch file:
- [ ] **G5** upgrade-batch-reviewed — PASS date / reviewer:
- [ ] **S5** Sign & execute the proxy-upgrade batch — date / by:
      tx hash(es):
- [ ] **G6** upgrade-complete — PASS date / by:

### Phase C — Activation

- [ ] **S5a** Pause RecurringCollector (DIPs dormant) — guardian / date / by:
      tx hash:
- [ ] **G6a** dips-dormant (`RC.paused() == true`) — PASS date / by:
- [ ] **S6** Generate the eligibility-integrate batch — date / by:
      batch file:
- [ ] **G7** eligibility-batch-reviewed — PASS date / reviewer:
- [ ] **S7** Sign & execute the eligibility-integrate batch — date / by:
      tx hash(es):
- [ ] **G8** eligibility-active — PASS date / by:
- [ ] **S8** Generate the issuance-connect batch — date / by:
      batch file:
- [ ] **G9** connect-batch-reviewed — PASS date / reviewer:
- [ ] **S9** Sign & execute the issuance-connect batch — date / by:
      tx hash(es):
- [ ] **G10** issuance-connected — PASS date / by:
- [ ] **S10** Generate the issuance-allocate batch — date / by:
      batch file:
- [ ] **G11** allocate-batch-reviewed — PASS date / reviewer:
- [ ] **S11** Sign & execute the issuance-allocate batch — date / by:
      tx hash(es):
- [ ] **G12** rollout-complete — PASS date / by:

### Phase D — Off-chain rollout & close-out

- [ ] **S12** Publish address book & bump shared packages — date / by:
- [ ] **G13** packages-published — PASS date / by:
- [ ] **S13** Release off-chain components — date / by:
- [ ] **G14** offchain-released — PASS date / by:
- [ ] **S14** Run manual testnet test plans — date / by:
- [ ] **G15** test-plans-passed — PASS date / by:
      test-plan results:
- [ ] **S15** Comms, security & indexer upgrade window — date / by:
- [ ] **G16** go-live-complete — PASS date / by:

## Waivers & N/A gates

Record every gate marked done without meeting its full pass criterion — and why.

| Gate | Waived / N/A | Reason |
| ---- | ------------ | ------ |
|      |              |        |

## Notes & deviations

-
