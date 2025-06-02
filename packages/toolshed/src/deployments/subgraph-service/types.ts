import type {
  IDisputeManager,
  IL2CurationToolshed,
  IServiceRegistryToolshed,
} from '@graphprotocol/subgraph-service'

import {
  L2GNS,
} from '../horizon'

// These are just type re-declarations to keep naming conventions consistent
export {
  IL2CurationToolshed as L2Curation,
  L2GNS,
  IDisputeManager as LegacyDisputeManager,
  IServiceRegistryToolshed as LegacyServiceRegistry,
}
