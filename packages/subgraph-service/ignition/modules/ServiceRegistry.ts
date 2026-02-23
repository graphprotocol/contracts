import ServiceRegistryArtifact from '@graphprotocol/contracts/artifacts/contracts/discovery/ServiceRegistry.sol/ServiceRegistry.json'
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('ServiceRegistry', (m) => {
  const legacyServiceRegistryAddress = m.getParameter('legacyServiceRegistryAddress')

  const LegacyServiceRegistry = m.contractAt(
    'LegacyServiceRegistry',
    ServiceRegistryArtifact,
    legacyServiceRegistryAddress,
  )

  return {
    LegacyServiceRegistry,
  }
})
