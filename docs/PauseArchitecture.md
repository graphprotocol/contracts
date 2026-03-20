# Pause Architecture

This document describes the layered pause mechanisms available for the recurring
agreement / collection subsystem. Each layer is independently controlled and
targets a different blast radius.

## Pause Layers

### 1. RecurringAgreementManager (RAM) pause

|                   |                                                               |
| ----------------- | ------------------------------------------------------------- |
| **Scope**         | Single RAM instance                                           |
| **Controlled by** | `PAUSE_ROLE` (admin: `GOVERNOR_ROLE`)                         |
| **Mechanism**     | OpenZeppelin `PausableUpgradeable` (`whenNotPaused` modifier) |

**Functions blocked when paused:**

- `offerAgreement` / `offerAgreementUpdate` — no new offers or updates
- `revokeAgreementUpdate` / `revokeOffer` — no revocations
- `cancelAgreement` — no cancellations
- `approveAgreement` — returns `bytes4(0)`, preventing the RecurringCollector
  from accepting or updating agreements that use contract-approval authorization

**Functions that continue to work:**

- `beforeCollection` / `afterCollection` — collection callbacks remain
  operational so providers can collect earned payments
- `reconcileAgreement` / `reconcileCollectorProvider` — permissionless
  reconciliation

**When to use:** Problems with agreement terms, offer logic, or escrow
management within the RAM. Stops new obligations from being created while
allowing providers to collect what they have already earned.

### 2. RecurringCollector pause

|                   |                                                          |
| ----------------- | -------------------------------------------------------- |
| **Scope**         | Single RecurringCollector instance (all payers using it) |
| **Controlled by** | Pause guardians (set by governor via `setPauseGuardian`) |
| **Mechanism**     | OpenZeppelin `Pausable` (`whenNotPaused` modifier)       |

**Functions blocked when paused:**

- `accept` — no new agreement acceptances
- `update` — no agreement updates
- `collect` — no payment collections
- `cancel` — no agreement cancellations

**When to use:** Problem with the collection or escrow logic that could be
exploited through ongoing collections. This is a significant action because it
prevents providers from collecting earned payments, and collection windows are
time-bounded — a pause doesn't just delay collection, it can reduce or eliminate
what is collectible.

### 3. Eligibility checker (RAM-level, per-agreement)

|                   |                                                              |
| ----------------- | ------------------------------------------------------------ |
| **Scope**         | All contract-approved agreements for a specific RAM          |
| **Controlled by** | RAM admin (configures eligibility checker contract)          |
| **Mechanism**     | `IProviderEligibility.isEligible` callback during collection |

Setting an eligibility checker that always returns `false` blocks collections
for all contract-approved agreements managed by that RAM. This does **not**
affect signature-based agreements.

**When to use:** Need to block collections for a specific payer's agreements
without affecting other payers on the same collector.

### 4. Controller pause (protocol-wide)

|                   |                                                                          |
| ----------------- | ------------------------------------------------------------------------ |
| **Scope**         | All contracts that check `Controller.paused()`                           |
| **Controlled by** | Governor / pause guardian on the Controller                              |
| **Mechanism**     | `PaymentsEscrow.notPaused` modifier checks `_graphController().paused()` |

**Functions blocked when paused:**

- `PaymentsEscrow.deposit` / `depositTo` / `thaw` / `withdraw` / `collect`
- Any other contract checking controller pause state

**When to use:** Protocol-wide emergency. Nuclear option that halts all escrow
operations across every payer and collector.

## Decision Guide

| Scenario                                              | Recommended action                     |
| ----------------------------------------------------- | -------------------------------------- |
| Bug in RAM offer/escrow logic                         | Pause RAM                              |
| Bug in collection execution logic                     | Pause RecurringCollector               |
| Need to block one RAM's contract-approved collections | Configure deny-all eligibility checker |
| Protocol-wide emergency                               | Pause Controller                       |
| Full halt of recurring agreement subsystem            | Pause RAM + RecurringCollector         |
