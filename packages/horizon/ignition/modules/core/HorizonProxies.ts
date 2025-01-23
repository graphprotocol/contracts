import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployGraphProxy } from '../proxy/GraphProxy'
import { deployTransparentUpgradeableProxy } from '../proxy/TransparentUpgradeableProxy'
import { ethers } from 'ethers'

import GraphPeripheryModule from '../periphery/periphery'

import GraphPaymentsArtifact from '../../../build/contracts/contracts/payments/GraphPayments.sol/GraphPayments.json'
import PaymentsEscrowArtifact from '../../../build/contracts/contracts/payments/PaymentsEscrow.sol/PaymentsEscrow.json'

// HorizonStaking, GraphPayments and PaymentsEscrow use GraphDirectory but they are also in the directory.
// So we need to deploy their proxies, register them in the controller before being able to deploy the implementations
export default buildModule('HorizonProxies', (m) => {
  const { Controller, GraphProxyAdmin } = m.useModule(GraphPeripheryModule)

  // Deploy HorizonStaking proxy with no implementation
  const HorizonStakingProxy = deployGraphProxy(m, GraphProxyAdmin)
  m.call(Controller, 'setContractProxy',
    [ethers.keccak256(ethers.toUtf8Bytes('Staking')), HorizonStakingProxy],
    { id: 'setContractProxy_HorizonStaking' },
  )

  // Deploy GraphPayments proxy
  const { Proxy: GraphPaymentsProxy, ProxyAdmin: GraphPaymentsProxyAdmin } = deployTransparentUpgradeableProxy(m, {
    name: 'GraphPayments',
    artifact: GraphPaymentsArtifact,
  })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphPayments')), GraphPaymentsProxy], { id: 'setContractProxy_GraphPayments' })

  // Deploy PaymentsEscrow proxy
  const { Proxy: PaymentsEscrowProxy, ProxyAdmin: PaymentsEscrowProxyAdmin } = deployTransparentUpgradeableProxy(m, {
    name: 'PaymentsEscrow',
    artifact: PaymentsEscrowArtifact,
  })
  m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('PaymentsEscrow')), PaymentsEscrowProxy], { id: 'setContractProxy_PaymentsEscrow' })

  return { HorizonStakingProxy, GraphPaymentsProxy, PaymentsEscrowProxy, GraphPaymentsProxyAdmin, PaymentsEscrowProxyAdmin }
})

// export const UpgradeHorizonProxiesModule = buildModule('HorizonProxies', (m) => {
//   const governor = m.getAccount(1)

//   const controllerAddress = m.getParameter('controllerAddress')

//   // Deploy proxies for payments contracts using OZ TransparentUpgradeableProxy
//   const { Proxy: GraphPaymentsProxy, ProxyAdmin: GraphPaymentsProxyAdmin } = deployWithOZProxy(m, 'GraphPayments')
//   const { Proxy: PaymentsEscrowProxy, ProxyAdmin: PaymentsEscrowProxyAdmin } = deployWithOZProxy(m, 'PaymentsEscrow')

//   // Register the proxies in the controller
//   const Controller = m.contractAt('Controller', controllerAddress, { id: 'Controller' })
//   m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphPayments')), GraphPaymentsProxy], { id: 'setContractProxy_GraphPayments', from: governor })
//   m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('PaymentsEscrow')), PaymentsEscrowProxy], { id: 'setContractProxy_PaymentsEscrow', from: governor })

//   return { GraphPaymentsProxy, PaymentsEscrowProxy, GraphPaymentsProxyAdmin, PaymentsEscrowProxyAdmin }
// })
