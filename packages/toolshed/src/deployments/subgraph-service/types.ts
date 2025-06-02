import type {
  IDisputeManager,
  IGNSToolshed,
  IL2CurationToolshed,
  IServiceRegistryToolshed,
  ISubgraphNFT,
} from '@graphprotocol/subgraph-service'

// These are just type re-declarations to keep naming conventions consistent
export {
  IL2CurationToolshed as L2Curation,
  IGNSToolshed as L2GNS,
  IDisputeManager as LegacyDisputeManager,
  IServiceRegistryToolshed as LegacyServiceRegistry,
  ISubgraphNFT as SubgraphNFT,
}
