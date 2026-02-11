# Ensure indexer agent starts in horizon mode

Gabriel: Done
tmigone: Done
Marc-Andre: Done
Vincent: Done
Man4ela: Done
p2p: Not started

Once horizon is live the indexer agent should start in horizon mode, to verify this search the logs for the following:

```bash
[10:40:15.218] DEBUG (IndexerAgent/1): Check if network is Horizon ready
    component: "Network"
    indexer: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
    protocolNetwork: "eip155:421614"
    operator: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
[10:40:15.218] INFO (IndexerAgent/1): Network is Horizon ready
    component: "Network"
    indexer: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
    protocolNetwork: "eip155:421614"
    operator: "0xb0188c4d02eAB4D444c1678f1EDe9F790fFc838e"
```