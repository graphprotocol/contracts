import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { ethers } from 'ethers'

import GraphPaymentsArtifact from '../../../build/contracts/contracts/payments/GraphPayments.sol/GraphPayments.json'
import PaymentsEscrowArtifact from '../../../build/contracts/contracts/payments/PaymentsEscrow.sol/PaymentsEscrow.json'
import RecurringCollectorArtifact from '../../../build/contracts/contracts/payments/collectors/RecurringCollector.sol/RecurringCollector.json'
import { MigrateControllerGovernorModule } from '../periphery/Controller'
import GraphPeripheryModule from '../periphery/periphery'
import { deployGraphProxy } from '../proxy/GraphProxy'
import { deployTransparentUpgradeableProxy } from '../proxy/TransparentUpgradeableProxy'

// HorizonStaking, GraphPayments and PaymentsEscrow use GraphDirectory but they are also in the directory.
// So we need to deploy their proxies, register them in the controller before being able to deploy the implementations
export default buildModule('HorizonProxies', (m) => {
  const { Controller, GraphProxyAdmin } = m.useModule(GraphPeripheryModule)

  // Deploy HorizonStaking proxy with no implementation
  const HorizonStakingProxy = deployGraphProxy(m, GraphProxyAdmin)
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('Staking')), HorizonStakingProxy], {
    id: 'setContractProxy_HorizonStaking',
  })

  // Deploy and register GraphPayments proxy
  const { Proxy: GraphPaymentsProxy, ProxyAdmin: GraphPaymentsProxyAdmin } = deployTransparentUpgradeableProxy(m, {
    name: 'GraphPayments',
    artifact: GraphPaymentsArtifact,
  })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphPayments')), GraphPaymentsProxy], {
    id: 'setContractProxy_GraphPayments',
  })

  // Deploy and register PaymentsEscrow proxy
  const { Proxy: PaymentsEscrowProxy, ProxyAdmin: PaymentsEscrowProxyAdmin } = deployTransparentUpgradeableProxy(m, {
    name: 'PaymentsEscrow',
    artifact: PaymentsEscrowArtifact,
  })
  m.call(
    Controller,
    'setContractProxy',
    [ethers.keccak256(ethers.toUtf8Bytes('PaymentsEscrow')), PaymentsEscrowProxy],
    { id: 'setContractProxy_PaymentsEscrow' },
  )

  // Deploy RecurringCollector proxy (not registered in Controller — RC reads from Controller but is not looked up by others)
  const { Proxy: RecurringCollectorProxy, ProxyAdmin: RecurringCollectorProxyAdmin } =
    deployTransparentUpgradeableProxy(m, {
      name: 'RecurringCollector',
      artifact: RecurringCollectorArtifact,
    })

  return {
    HorizonStakingProxy,
    GraphPaymentsProxy,
    PaymentsEscrowProxy,
    RecurringCollectorProxy,
    GraphPaymentsProxyAdmin,
    PaymentsEscrowProxyAdmin,
    RecurringCollectorProxyAdmin,
  }
})

export const MigrateHorizonProxiesDeployerModule = buildModule('HorizonProxiesDeployer', (m) => {
  // Deploy GraphPayments proxy
  const { Proxy: GraphPaymentsProxy, ProxyAdmin: GraphPaymentsProxyAdmin } = deployTransparentUpgradeableProxy(m, {
    name: 'GraphPayments',
    artifact: GraphPaymentsArtifact,
  })

  // Deploy PaymentsEscrow proxy
  const { Proxy: PaymentsEscrowProxy, ProxyAdmin: PaymentsEscrowProxyAdmin } = deployTransparentUpgradeableProxy(m, {
    name: 'PaymentsEscrow',
    artifact: PaymentsEscrowArtifact,
  })

  // Deploy RecurringCollector proxy
  const { Proxy: RecurringCollectorProxy, ProxyAdmin: RecurringCollectorProxyAdmin } =
    deployTransparentUpgradeableProxy(m, {
      name: 'RecurringCollector',
      artifact: RecurringCollectorArtifact,
    })

  return {
    GraphPaymentsProxy,
    PaymentsEscrowProxy,
    RecurringCollectorProxy,
    GraphPaymentsProxyAdmin,
    PaymentsEscrowProxyAdmin,
    RecurringCollectorProxyAdmin,
  }
})

export const MigrateHorizonProxiesGovernorModule = buildModule('HorizonProxiesGovernor', (m) => {
  const { Controller } = m.useModule(MigrateControllerGovernorModule)

  const graphPaymentsAddress = m.getParameter('graphPaymentsAddress')
  const paymentsEscrowAddress = m.getParameter('paymentsEscrowAddress')

  // Register proxies in controller
  m.call(
    Controller,
    'setContractProxy',
    [ethers.keccak256(ethers.toUtf8Bytes('GraphPayments')), graphPaymentsAddress],
    { id: 'setContractProxy_GraphPayments' },
  )

  m.call(
    Controller,
    'setContractProxy',
    [ethers.keccak256(ethers.toUtf8Bytes('PaymentsEscrow')), paymentsEscrowAddress],
    { id: 'setContractProxy_PaymentsEscrow' },
  )

  return { Controller }
})
