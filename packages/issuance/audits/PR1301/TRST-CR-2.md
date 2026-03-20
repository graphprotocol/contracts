# TRST-CR-2: Operator role controls agreement lifecycle and escrow mode

- **Severity:** Centralization Risk

## Description

The `OPERATOR_ROLE` (admin of `AGREEMENT_MANAGER_ROLE`) controls the operational layer of the RAM:

- Grants `AGREEMENT_MANAGER_ROLE`, which authorizes offering, updating, revoking, and canceling agreements
- Can change the `escrowBasis` (Full/OnDemand/JIT), instantly affecting escrow behavior for all existing agreements
- Can set `tempJit`, overriding the escrow mode to JIT for all pairs

An operator switching from Full to JIT mode instantly removes proactive escrow guarantees for all providers. Providers who accepted agreements under the assumption of Full escrow backing may find their payment security degraded without notice or consent. The escrow mode change is a storage write with no timelock or multi-sig requirement.
