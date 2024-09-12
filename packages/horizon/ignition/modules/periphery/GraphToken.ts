import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployWithGraphProxy } from '../lib/proxy'

import GraphTokenGatewayModule from '../periphery/GraphTokenGateway'
import RewardsManagerModule from '../periphery/RewardsManager'

import GraphTokenArtifact from '@graphprotocol/contracts/build/contracts/contracts/l2/token/L2GraphToken.sol/L2GraphToken.json'

// TODO: Ownership transfer is a two step process, the new owner needs to accept it by calling acceptOwnership
export default buildModule('GraphToken', (m) => {
  const { RewardsManager } = m.useModule(RewardsManagerModule)
  const { GraphTokenGateway } = m.useModule(GraphTokenGatewayModule)

  const deployer = m.getAccount(0)
  const governor = m.getParameter('governor')
  const initialSupply = m.getParameter('initialSupply')

  const { instance: GraphToken } = deployWithGraphProxy(m, {
    name: 'GraphToken',
    artifact: GraphTokenArtifact,
    args: [deployer],
  })

  // Note that this next mint would only be done in L1
  m.call(GraphToken, 'mint', [deployer, initialSupply])
  m.call(GraphToken, 'renounceMinter', [])
  m.call(GraphToken, 'addMinter', [RewardsManager], { id: 'addMinterRewardsManager' })
  m.call(GraphToken, 'addMinter', [GraphTokenGateway], { id: 'addMinterGateway' })
  m.call(GraphToken, 'transferOwnership', [governor])

  return { GraphToken }
})
