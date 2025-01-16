import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployWithGraphProxy } from '../proxy/GraphProxy'

import GraphTokenGatewayModule from '../periphery/GraphTokenGateway'
import RewardsManagerModule from '../periphery/RewardsManager'

import GraphTokenArtifact from '@graphprotocol/contracts/build/contracts/contracts/l2/token/L2GraphToken.sol/L2GraphToken.json'

// TODO: Ownership transfer is a two step process, the new owner needs to accept it by calling acceptOwnership
export default buildModule('L2GraphToken', (m) => {
  const isMigrate = m.getParameter('isMigrate', false)

  let GraphToken
  if (isMigrate) {
    const graphTokenProxyAddress = m.getParameter('graphTokenProxyAddress')
    GraphToken = m.contractAt('GraphToken', GraphTokenArtifact, graphTokenProxyAddress)
  } else {
    const { instance: RewardsManager } = m.useModule(RewardsManagerModule)
    const { GraphTokenGateway } = m.useModule(GraphTokenGatewayModule)

    const deployer = m.getAccount(0)
    const governor = m.getParameter('governor')
    const initialSupply = m.getParameter('initialSupply')

    GraphToken = deployWithGraphProxy(m, {
      name: 'L2GraphToken',
      artifact: GraphTokenArtifact,
      args: [deployer],
    }).instance

    // TODO: move this mint to a testnet only module
    // Note that this next mint would only be done in L1
    m.call(GraphToken, 'mint', [deployer, initialSupply])
    m.call(GraphToken, 'renounceMinter', [])
    m.call(GraphToken, 'addMinter', [RewardsManager], { id: 'addMinterRewardsManager' })
    m.call(GraphToken, 'addMinter', [GraphTokenGateway], { id: 'addMinterGateway' })
    m.call(GraphToken, 'transferOwnership', [governor])
  }

  return { GraphToken }
})
