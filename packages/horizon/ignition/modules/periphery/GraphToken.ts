import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployWithGraphProxy } from '../proxy/GraphProxy'

import GraphProxyAdminModule from '../periphery/GraphProxyAdmin'
import GraphTokenGatewayModule from '../periphery/GraphTokenGateway'
import RewardsManagerModule from '../periphery/RewardsManager'

import GraphTokenArtifact from '@graphprotocol/contracts/build/contracts/contracts/l2/token/L2GraphToken.sol/L2GraphToken.json'

export default buildModule('L2GraphToken', (m) => {
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)
  const { RewardsManager } = m.useModule(RewardsManagerModule)
  const { GraphTokenGateway } = m.useModule(GraphTokenGatewayModule)

  const deployer = m.getAccount(0)
  const governor = m.getAccount(1)
  const initialSupply = m.getParameter('initialSupply')

  const GraphToken = deployWithGraphProxy(m, GraphProxyAdmin, {
    name: 'L2GraphToken',
    artifact: GraphTokenArtifact,
    initArgs: [deployer],
  })

  const mintCall = m.call(GraphToken, 'mint', [deployer, initialSupply])
  const renounceMinterCall = m.call(GraphToken, 'renounceMinter', [])
  const addMinterRewardsManagerCall = m.call(GraphToken, 'addMinter', [RewardsManager], { id: 'addMinterRewardsManager' })
  const addMinterGatewayCall = m.call(GraphToken, 'addMinter', [GraphTokenGateway], { id: 'addMinterGateway' })

  // No further calls are needed so we can transfer ownership now
  const transferOwnershipCall = m.call(GraphToken, 'transferOwnership', [governor], { after: [mintCall, renounceMinterCall, addMinterRewardsManagerCall, addMinterGatewayCall] })
  m.call(GraphToken, 'acceptOwnership', [], { from: governor, after: [transferOwnershipCall] })

  return { GraphToken }
})

export const MigrateGraphTokenModule = buildModule('L2GraphToken', (m) => {
  const graphTokenAddress = m.getParameter('graphTokenAddress')

  const GraphToken = m.contractAt('L2GraphToken', GraphTokenArtifact, graphTokenAddress)

  return { GraphToken }
})
