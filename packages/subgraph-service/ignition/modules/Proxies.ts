import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
// import { deployGraphProxy } from '../../../horizon/ignition/modules/proxy/GraphProxy'
import { deployTransparentUpgradeableProxy } from '@graphprotocol/horizon/ignition/modules/proxy/TransparentUpgradeableProxy'
// import { ethers } from 'ethers'

// import ControllerArtifact from '@graphprotocol/contracts/build/contracts/contracts/governance/Controller.sol/Controller.json'
import DisputeManagerArtifact from '../../build/contracts/contracts/DisputeManager.sol/DisputeManager.json'
// import GraphProxyAdminArtifact from '@graphprotocol/contracts/build/contracts/contracts/upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json'
import SubgraphServiceArtifact from '../../build/contracts/contracts/SubgraphService.sol/SubgraphService.json'

export default buildModule('SubgraphServiceProxies', (m) => {
  // const graphProxyAdminAddress = m.getParameter('graphProxyAdminAddress')
  // const controllerAddress = m.getParameter('controllerAddress')

  // const GraphProxyAdmin = m.contractAt('GraphProxyAdmin', GraphProxyAdminArtifact, graphProxyAdminAddress)
  // const Controller = m.contractAt('Controller', ControllerArtifact, controllerAddress)

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

  // // Deploy Curation proxy with no implementation
  // const L2CurationProxy = deployGraphProxy(m, GraphProxyAdmin)
  // m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('Curation')), L2CurationProxy], { id: 'setContractProxy_L2Curation' })

  return {
    SubgraphServiceProxy,
    SubgraphServiceProxyAdmin,
    DisputeManagerProxy,
    DisputeManagerProxyAdmin,
    // L2CurationProxy,
  }
})
