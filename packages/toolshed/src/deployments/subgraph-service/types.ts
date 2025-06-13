import type {
  IDisputeManager,
  IGNSToolshed,
  IL2CurationToolshed,
  IServiceRegistryToolshed,
  ISubgraphNFT,
  ISubgraphService,
} from '@graphprotocol/interfaces'

// These are just type re-declarations to keep naming conventions consistent
export {
  IDisputeManager as DisputeManager,
  IL2CurationToolshed as L2Curation,
  IGNSToolshed as L2GNS,
  IDisputeManager as LegacyDisputeManager,
  IServiceRegistryToolshed as LegacyServiceRegistry,
  ISubgraphNFT as SubgraphNFT,
  ISubgraphService as SubgraphService,
}
