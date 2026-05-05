# TRST-SR-1: JIT mode provider payment race condition

- **Severity:** Systemic Risk

## Description

When the RecurringAgreementManager operates in JustInTime (JIT) escrow mode, escrow is not proactively funded for any (collector, provider) pair. Instead, funds are deposited into escrow only during the `beforeCollection()` callback, moments before `PaymentsEscrow.collect()` executes. Since the RAM holds a shared pool of GRT that backs all agreements, multiple providers collecting around the same time are effectively racing for the same pool of tokens.

If the RAM's balance is sufficient to cover any single collection but not all concurrent collections, the provider whose data service submits the `collect()` transaction first will succeed, while subsequent providers' collections will revert because the RAM's balance has been depleted by the first collection's JIT deposit. This creates a first-come-first-served dynamic where providers must compete on transaction ordering to receive payment.

This race condition is inherent to the JIT mode design and cannot be fully eliminated without proactive escrow funding. In extreme cases, a well-resourced provider could use priority gas auctions or private mempools to consistently front-run other providers' collections, creating an unfair payment advantage unrelated to service quality.

---

Known architectural tradeoff. Full mode eliminates this entirely; OnDemand reduces its likelihood. JIT provides best-effort payment guarantees and is the fallback when the RAM's balance cannot sustain proactive escrow funding.
