# The Graph Name Service (GNS) Registry Contract

## Requirements:
- Maps names to `subgraphId`
- Namespace owners control names within a namespace
- Top-level registrar assigns names to Ethereum Addresses
- Mapping a name to a `subgraphId` also requires curating that `subgraphId`.
- No contracts depend on the GNS Registry, but rather is consumed by users of The Graph.