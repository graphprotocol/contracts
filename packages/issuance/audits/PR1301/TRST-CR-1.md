# TRST-CR-1: RAM Governor has unilateral control over payment infrastructure

- **Severity:** Centralization Risk

## Description

The RecurringAgreementManager's `GOVERNOR_ROLE` has broad unilateral authority over critical payment infrastructure:

- Controls which data services can participate (`DATA_SERVICE_ROLE` grants)
- Controls which collectors are trusted (`COLLECTOR_ROLE` grants)
- Can set the issuance allocator address, redirecting the token flow that funds all escrow
- Can set the provider eligibility oracle, which gates who can receive payments
- Can pause the entire contract, halting all agreement management

A compromised or malicious governor could revoke a data service's role (preventing new agreements), change the issuance allocator to a contract that withholds funds, or set a malicious eligibility oracle that blocks specific providers from collecting. These actions affect all agreements managed by the RAM, not just future ones.

---

Accepted centralization tradeoff. The governor must have these powers for effective protocol operation. Expected to be a multisig or governance contract in production.
