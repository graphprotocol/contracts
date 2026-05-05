# TRST-R-1: Avoid redeployment of the RewardsEligibilityOracle by restructuring storage

- **Severity:** Recommendation

## Description

The modified RewardsEligibilityOracle has two new state variables, as well as moving `eligibilityValidationEnabled` from the original slot to the end of the structure. Due to the relocation, an upgrade is needed, meaning all previous eligibility state will be lost. It is possible to only append storage slots to the original structure, and avoid a hard redeployment flow, by leveraging the upgradeability of the oracle.

---

Acknowledged. The oracle is not yet deployed to production so the storage restructuring does not lose live state. The current layout preserves clean append-only expansion for future upgrades.
