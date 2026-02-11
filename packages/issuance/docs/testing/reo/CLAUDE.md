# CLAUDE.md -- REO Testing Context

## What This Is

Test plans for the Rewards Eligibility Oracle (REO) upgrade to The Graph Protocol. Two-layer approach: baseline indexer tests (upgrade-agnostic) plus REO-specific tests.

**Start here**: Read [Status.md](./Status.md) first. It tracks current phase, next step, and has the full research findings.

## Key Files

| File | Purpose |
|------|---------|
| [Status.md](./Status.md) | Current state, next steps, research findings. **Update after every step.** |
| [Goal.md](./Goal.md) | Objective and deliverables overview |
| [BaselineTestPlan.md](./BaselineTestPlan.md) | 7 cycles, 22 tests -- upgrade-agnostic indexer operations |
| [ReoTestPlan.md](./ReoTestPlan.md) | 8 cycles, 30 tests -- REO-specific eligibility, oracle, rewards |
| [notion/](./notion/) | Raw Notion exports from Horizon testing (source material for baseline) |

## Repository Layout

This is a git worktree of the contracts monorepo. Multiple worktrees exist side by side:

```
/git/graphprotocol/contracts/
├── main/              # main branch
├── post-audit/        # latest issuance/REO contract source code
├── reo-testing/       # THIS worktree (reo-testing branch)
└── ...                # other feature worktrees
```

**Source contracts** (read-only reference, do not edit here):
- REO contract: `../../../post-audit/packages/issuance/contracts/eligibility/`
- REO spec: `../../../post-audit/packages/issuance/contracts/eligibility/RewardsEligibilityOracle.md`
- IssuanceAllocator: `../../../post-audit/packages/issuance/contracts/allocate/`
- Deployment scripts: `../../../post-audit/packages/deployment/deploy/`
- Audit reports: `../../../post-audit/packages/issuance/audits/`

## REO in 30 Seconds

- `RewardsEligibilityOracle` -- deny-by-default eligibility for indexer rewards
- `isEligible(indexer)` returns true if: validation disabled OR renewed within period OR oracle timeout
- Defaults: validation off, 14-day eligibility period, 7-day oracle timeout
- Roles: Governor > Operator > Oracle, plus Pause
- Integration: `RewardsManager.setRewardsEligibilityOracle(REO)`
- Deployed on Arbitrum Sepolia: proxy `0x62c2305739cc75f19a3a6d52387ceb3690d99a99`

## Workflow

1. Read Status.md to see what's next
2. Do the work
3. Update Status.md (phase, progress table, history)
4. Commit
5. Repeat
