import type {
  ICuration,
  IDisputeManager,
  IL2GNS,
} from '@graphprotocol/subgraph-service'

import type { IServiceRegistry } from '@graphprotocol/contracts'

// These are just type re-declarations to keep naming conventions consistent
export {
  ICuration as L2Curation,
  IL2GNS as L2GNS,
  IDisputeManager as LegacyDisputeManager,
  IServiceRegistry as LegacyServiceRegistry,
}
