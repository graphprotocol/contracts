import { ArgumentType, Artifact, ContractDeploymentFuture, IgnitionModuleBuilder } from '@nomicfoundation/ignition-core'
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import ControllerArtifact from '@graphprotocol/contracts/build/contracts/contracts/governance/Controller.sol/Controller.json'
import GraphProxyAdminArtifact from '@graphprotocol/contracts/build/contracts/contracts/upgrades/GraphProxyAdmin.sol/GraphProxyAdmin.json'
import GraphProxyArtifact from '@graphprotocol/contracts/build/contracts/contracts/upgrades/GraphProxy.sol/GraphProxy.json'
import RewardsManagerArtifact from '@graphprotocol/contracts/build/contracts/contracts/rewards/RewardsManager.sol/RewardsManager.json'

function deployWithGraphProxy(m: IgnitionModuleBuilder, proxyAdmin: ContractDeploymentFuture, contract: { name: string, artifact?: Artifact, args?: ArgumentType[] }) {
  // Deploy implementation
  let implementation
  if (contract.artifact === undefined) {
    implementation = m.contract(contract.name)
  } else {
    implementation = m.contract(contract.name, contract.artifact)
  }

  // Deploy proxy and initialize
  const proxy = m.contract('GraphProxy', GraphProxyArtifact, [implementation, proxyAdmin])
  if (contract.args === undefined) {
    m.call(proxyAdmin, 'acceptProxy', [implementation, proxy])
  } else {
    m.call(proxyAdmin, 'acceptProxyAndCall', [implementation, proxy, m.encodeFunctionCall(implementation, 'initialize', contract.args)])
  }

  // Load proxy with implementation ABI
  let instance
  if (contract.artifact === undefined) {
    instance = m.contractAt(contract.name, proxy)
  } else {
    instance = m.contractAt(`${contract.name}_Instance`, contract.artifact, proxy)
  }

  return { proxy, implementation, instance }
}

export default buildModule('GraphHorizon_Periphery', (m) => {
  // GraphProxyAdmin
  const GraphProxyAdmin = m.contract('GraphProxyAdmin', GraphProxyAdminArtifact)
  m.call(GraphProxyAdmin, 'transferOwnership', [m.getParameter('Accounts_governor')])

  // Controller
  const Controller = m.contract('Controller', ControllerArtifact)

  // RewardsManager
  const { instance: RewardsManager } = deployWithGraphProxy(m, GraphProxyAdmin, {
    name: 'RewardsManager',
    artifact: RewardsManagerArtifact,
    args: [Controller],
  })
  m.call(RewardsManager, 'setIssuancePerBlock', [m.getParameter('RewardsManager_issuancePerBlock')])
<<<<<<< Updated upstream
  // eslint-disable-next-line no-secrets/no-secrets
=======
>>>>>>> Stashed changes
  m.call(RewardsManager, 'setSubgraphAvailabilityOracle', [m.getParameter('Accounts_subgraphAvailabilityOracle')])
  m.call(RewardsManager, 'syncAllContracts')

  return { GraphProxyAdmin, Controller, RewardsManager }
})
