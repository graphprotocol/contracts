import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployWithGraphProxy } from '../proxy/GraphProxy'

import GraphProxyAdminModule from '../periphery/GraphProxyAdmin'
import GraphTokenGatewayModule from '../periphery/GraphTokenGateway'
import RewardsManagerModule from '../periphery/RewardsManager'

import GraphTokenArtifact from '@graphprotocol/contracts/build/contracts/contracts/l2/token/L2GraphToken.sol/L2GraphToken.json'

export default buildModule('L2GraphToken', (m) => {
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)
  const { RewardsManager } = m.useModule(RewardsManagerModule)
  const { L2GraphTokenGateway } = m.useModule(GraphTokenGatewayModule)

  const deployer = m.getAccount(0)
  const governor = m.getAccount(1)
  const initialSupply = m.getParameter('initialSupply')

  const L2GraphToken = deployWithGraphProxy(m, GraphProxyAdmin, {
    name: 'L2GraphToken',
    artifact: GraphTokenArtifact,
    initArgs: [deployer],
  })

  const mintCall = m.call(L2GraphToken, 'mint', [deployer, initialSupply])
  const renounceMinterCall = m.call(L2GraphToken, 'renounceMinter', [])
  const addMinterRewardsManagerCall = m.call(L2GraphToken, 'addMinter', [RewardsManager], { id: 'addMinterRewardsManager' })
  const addMinterGatewayCall = m.call(L2GraphToken, 'addMinter', [L2GraphTokenGateway], { id: 'addMinterGateway' })

  // No further calls are needed so we can transfer ownership now
  const transferOwnershipCall = m.call(L2GraphToken, 'transferOwnership', [governor], { after: [mintCall, renounceMinterCall, addMinterRewardsManagerCall, addMinterGatewayCall] })
  m.call(L2GraphToken, 'acceptOwnership', [], { from: governor, after: [transferOwnershipCall] })

  return { L2GraphToken }
})

export const MigrateGraphTokenModule = buildModule('L2GraphToken', (m) => {
  const graphTokenAddress = m.getParameter('graphTokenAddress')

  const L2GraphToken = m.contractAt('L2GraphToken', GraphTokenArtifact, graphTokenAddress)

  return { L2GraphToken }
})
