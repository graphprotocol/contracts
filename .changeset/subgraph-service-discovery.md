---
'@graphprotocol/subgraph-service': minor
---

Add L2GNS, GNS, L2Curation, their storage contracts and Multicall, ported from `@graphprotocol/contracts` to Solidity 0.8.35 with the same behaviour and storage layout, plus `InitializableV3`, a copy of OpenZeppelin 3.4.2's `Initializable` that keeps its storage slots. The artifacts are `@graphprotocol/subgraph-service/artifacts/contracts/l2/curation/L2Curation.sol/L2Curation.json` and `@graphprotocol/subgraph-service/artifacts/contracts/l2/discovery/L2GNS.sol/L2GNS.json`.
