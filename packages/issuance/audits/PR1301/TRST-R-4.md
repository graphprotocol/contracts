# TRST-R-4: Document critical assumptions in the RAM

- **Severity:** Recommendation

## Description

The `approveAgreement()` view checks if the agreement hash is valid, however it offers no replay protection for repeated agreement approvals. This attack vector is only stopped at the RecurringCollector as it checks the agreement does not exist and maintains unidirectional transitions from the agreement Accepted state. For future collectors this may not be the case, necessitating clear documentation of the assumption.

---

Fixed. Decoupled claim formula from RAM into RC (`computeMaxFirstClaim`/`computeMaxUpdateClaim`), fixed escrow accounting to max-based model, and added NatSpec WARNING to `IAgreementOwner.approveAgreement()` documenting the replay protection assumption.
