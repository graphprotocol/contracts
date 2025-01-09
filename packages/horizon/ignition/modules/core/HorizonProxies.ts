import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployWithOZProxy } from '../proxy/TransparentUpgradeableProxy'
import { ethers } from 'ethers'

import GraphPeripheryModule from '../periphery'
import GraphProxyAdminModule from '../periphery/GraphProxyAdmin'

import DummyArtifact from '../../../build/contracts/contracts/mocks/Dummy.sol/Dummy.json'
import GraphProxyArtifact from '@graphprotocol/contracts/build/contracts/contracts/upgrades/GraphProxy.sol/GraphProxy.json'

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

// HorizonStaking, GraphPayments and PaymentsEscrow use GraphDirectory but they also in the directory.
// So we need to deploy their proxies, register them in the controller before being able to deploy the implementations
export default buildModule('HorizonProxies', (m) => {
  const { Controller, PeripheryRegistered } = m.useModule(GraphPeripheryModule)
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)

  const isMigrate = m.getParameter('isMigrate', false)

  // Deploy HorizonStaking proxy without an implementation
  let HorizonStakingProxy, setProxyHorizonStaking
  if (isMigrate) {
    const horizonStakingProxyAddress = m.getParameter('horizonStakingProxyAddress')
    HorizonStakingProxy = m.contractAt('GraphProxy', GraphProxyArtifact, horizonStakingProxyAddress, { id: 'GraphProxy_HorizonStaking' })
    setProxyHorizonStaking = HorizonStakingProxy
  } else {
    HorizonStakingProxy = m.contract('GraphProxy', GraphProxyArtifact, [ZERO_ADDRESS, GraphProxyAdmin], { after: [PeripheryRegistered], id: 'GraphProxy_HorizonStaking' })
    setProxyHorizonStaking = m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('Staking')), HorizonStakingProxy], { id: 'setContractProxy_HorizonStaking' })
  }

  // Deploy proxies for payments contracts using OZ TransparentUpgradeableProxy
  const { Proxy: GraphPaymentsProxy, ProxyAdmin: GraphPaymentsProxyAdmin } = deployWithOZProxy(m, 'GraphPayments')
  const { Proxy: PaymentsEscrowProxy, ProxyAdmin: PaymentsEscrowProxyAdmin } = deployWithOZProxy(m, 'PaymentsEscrow')

  // Register the proxies in the controller
  // if isMigrate then use from: governor
  const options = isMigrate ? { from: m.getAccount(1) } : {}
  const setProxyGraphPayments = m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphPayments')), GraphPaymentsProxy], { ...options, id: 'setContractProxy_GraphPayments' })
  const setProxyPaymentsEscrow = m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('PaymentsEscrow')), PaymentsEscrowProxy], { ...options, id: 'setContractProxy_PaymentsEscrow' })

  // Deploy dummy contract to signal that all periphery contracts are registered
  const HorizonRegistered = m.contract('Dummy', DummyArtifact, [], {
    id: 'RegisteredDummy',
    after: [
      setProxyHorizonStaking,
      setProxyGraphPayments,
      setProxyPaymentsEscrow,
    ],
  })

  return { HorizonStakingProxy, GraphPaymentsProxy, PaymentsEscrowProxy, HorizonRegistered, GraphPaymentsProxyAdmin, PaymentsEscrowProxyAdmin }
})
