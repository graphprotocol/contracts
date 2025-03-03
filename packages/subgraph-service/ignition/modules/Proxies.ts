import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployTransparentUpgradeableProxy } from '@graphprotocol/horizon/ignition/modules/proxy/TransparentUpgradeableProxy'

import DisputeManagerArtifact from '../../build/contracts/contracts/DisputeManager.sol/DisputeManager.json'
import SubgraphServiceArtifact from '../../build/contracts/contracts/SubgraphService.sol/SubgraphService.json'

export default buildModule('SubgraphServiceProxies', (m) => {
  // Deploy proxies contracts using OZ TransparentUpgradeableProxy
  const {
    Proxy: DisputeManagerProxy,
    ProxyAdmin: DisputeManagerProxyAdmin,
  } = deployTransparentUpgradeableProxy(m, {
    name: 'DisputeManager',
    artifact: DisputeManagerArtifact,
  })
  const {
    Proxy: SubgraphServiceProxy,
    ProxyAdmin: SubgraphServiceProxyAdmin,
  } = deployTransparentUpgradeableProxy(m, {
    name: 'SubgraphService',
    artifact: SubgraphServiceArtifact,
  })

  return {
    SubgraphServiceProxy,
    SubgraphServiceProxyAdmin,
    DisputeManagerProxy,
    DisputeManagerProxyAdmin,
  }
})
