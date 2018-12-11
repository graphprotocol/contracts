# The Graph Payment Channel Contract

## Requirements
- A (mostly) traditional Payment Channel contract (duh) between dApp End-User and Payment Channel Hub
- See Raiden Specification for reference payment channel: [https://raiden-network-specification.readthedocs.io/en/latest/smart_contracts.html#tokennetworkregistry-contract](https://raiden-network-specification.readthedocs.io/en/latest/smart_contracts.html#tokennetworkregistry-contract)
- Payments unlocked by query responses + attestations.
- Micropayments specify a max balance transfer
    - Actual balance transfer defined in the unlock message
- Payments are always one-way (from End-User to Payment Channel hub)