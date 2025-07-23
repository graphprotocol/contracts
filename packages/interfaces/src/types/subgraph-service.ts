import type {
  IDisputeManager, // typechain builds contracts interface as IDisputeManager
  IDisputeManagerToolshed, // typechain doesn't build this interface so we toolshed-it
  IL2GNSToolshed,
  IL2CurationToolshed,
  IServiceRegistryToolshed,
  ISubgraphNFT,
  ISubgraphServiceToolshed,
} from '../../types'

// These are just type re-declarations to keep naming conventions consistent
export {
  IDisputeManagerToolshed as DisputeManager,
  IL2CurationToolshed as L2Curation,
  IL2GNSToolshed as L2GNS,
  IDisputeManager as LegacyDisputeManager,
  IServiceRegistryToolshed as LegacyServiceRegistry,
  ISubgraphNFT as SubgraphNFT,
  ISubgraphServiceToolshed as SubgraphService,
}
