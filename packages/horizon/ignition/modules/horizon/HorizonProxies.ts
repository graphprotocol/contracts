import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { ethers } from 'ethers'

import GraphPeripheryModule from '../periphery'
import GraphProxyAdminModule from '../periphery/GraphProxyAdmin'

import GraphProxyArtifact from '@graphprotocol/contracts/build/contracts/contracts/upgrades/GraphProxy.sol/GraphProxy.json'

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

// HorizonStaking, GraphPayments and PaymentsEscrow use GraphDirectory but they also in the directory.
// So we need to deploy their proxies, register them in the controller before being able to deploy the implementations
export default buildModule('HorizonProxies', (m) => {
  const { Controller, PeripheryRegistered } = m.useModule(GraphPeripheryModule)
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)

  // Deploy HorizonStaking proxy without an implementation
  // TODO: GraphPayments and PaymentsEscrow dont use GraphProxy but use OZ
  const HorizonStakingProxy = m.contract('GraphProxy', GraphProxyArtifact, [ZERO_ADDRESS, GraphProxyAdmin], { after: [PeripheryRegistered], id: 'GraphProxy_HorizonStaking' })
  const GraphPaymentsProxy = m.contract('GraphProxy', GraphProxyArtifact, [ZERO_ADDRESS, GraphProxyAdmin], { after: [PeripheryRegistered], id: 'GraphProxy_GraphPayments' })
  const PaymentsEscrowProxy = m.contract('GraphProxy', GraphProxyArtifact, [ZERO_ADDRESS, GraphProxyAdmin], { after: [PeripheryRegistered], id: 'GraphProxy_PaymentsEscrow' })

  // Register the proxies in the controller
  const setProxyHorizonStaking = m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('Staking')), HorizonStakingProxy], { id: 'setContractProxy_HorizonStaking' })
  const setProxyGraphPayments = m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('GraphPayments')), GraphPaymentsProxy], { id: 'setContractProxy_GraphPayments' })
  const setProxyPaymentsEscrow = m.call(Controller, 'setContractProxy', [ethers.keccak256(ethers.toUtf8Bytes('PaymentsEscrow')), PaymentsEscrowProxy], { id: 'setContractProxy_PaymentsEscrow' })

  // Deploy dummy contract to signal that all periphery contracts are registered
  const HorizonRegistered = m.contract('Dummy', [], {
    after: [
      setProxyHorizonStaking,
      setProxyGraphPayments,
      setProxyPaymentsEscrow,
    ],
  })

  return { HorizonStakingProxy, GraphPaymentsProxy, PaymentsEscrowProxy, HorizonRegistered }
})
