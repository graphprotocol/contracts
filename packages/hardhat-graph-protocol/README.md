# hardhat-graph-protocol


## Usage

Install with pnpm

```bash
pnpm add --dev hardhat-graph-protocol

# From the monorepo
pnpm add --dev hardhat-graph-protocol@workspace:^x.y.z
```

And add it to your `hardhat.config.ts`:

```ts
import "hardhat-graph-protocol";

export default {
  ...
  graph: {
    deployments: {
      horizon: require.resolve('@graphprotocol/horizon/addresses.json'),
      subgraphService: require.resolve('@graphprotocol/subgraph-service/addresses.json'),
    }
  },
  ...
};
```

_Note_: When using the plugin from within this monorepo TypeScript fails to properly apply the type extension typings. This is a known issue and can be worked around by adding a `types/hardhat-graph-protocol.d.ts` file with the same content as the `type-extensions.ts` file in this repository.