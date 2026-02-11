# (optional) Ensure indexer agent still works even if misconfigured

Gabriel: Done
tmigone: Done
Marc-Andre: Done
Vincent: Done
Man4ela: Done
p2p: Not started

Only applies for setups that are running horizon compatible versions but have not configured the indexer properly (set provision max size, have 100k GRT unallocated, etc).

Essentially the indexer agent should not crash and should log the following (skip provisioning and registration depending on how misconfigured it is):

```bash
[10:40:15.416] INFO (IndexerAgent/1): Provision indexer to the Subgraph Service
    component: "Network"
    indexer: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
    protocolNetwork: "eip155:421614"
    operator: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
    address: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
    maxProvisionInitialSize: "0.0"
[10:40:15.416] INFO (IndexerAgent/1): Max provision initial size is 0, skipping provisioning. Please set to a non-zero value to enable Graph Horizon functionality.
    component: "Network"
    indexer: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
    protocolNetwork: "eip155:421614"
    operator: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
    address: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
[10:40:15.574] INFO (IndexerAgent/1): Indexer does not have a provision, skipping registration.
    component: "Network"
    indexer: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
    protocolNetwork: "eip155:421614"
    operator: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
```