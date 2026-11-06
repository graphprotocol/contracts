---
'@graphprotocol/horizon': patch
---

The dependency artifacts and types for `TokenUtils` and `GraphUpgradeable` are now built from `@graphprotocol/graph-token` and `@graphprotocol/graph-core`, so they move from `build/contracts/@graphprotocol/contracts/...` to `build/contracts/@graphprotocol/graph-token/...` and `build/contracts/@graphprotocol/graph-core/...`. Contract bytecode is unchanged.
