---
'@graphprotocol/issuance': minor
---

Add RewardsManager, ported from the former `contracts` package to Solidity 0.8.35 with the same behaviour and storage layout. Its artifact is `@graphprotocol/issuance/artifacts/contracts/rewards/RewardsManager.sol/RewardsManager.json`. `@graphprotocol/graph-core` and `@graphprotocol/interfaces` become dependencies, because the published sources import them.
