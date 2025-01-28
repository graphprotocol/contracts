import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployImplementation } from '../proxy/implementation'
import { upgradeTransparentUpgradeableProxyNoLoad } from '../proxy/TransparentUpgradeableProxy'

import GraphPeripheryModule, { MigratePeripheryModule } from '../periphery/periphery'
import HorizonProxiesModule, { MigrateHorizonProxiesDeployerModule } from './HorizonProxies'

import PaymentsEscrowArtifact from '../../../build/contracts/contracts/payments/PaymentsEscrow.sol/PaymentsEscrow.json'

export default buildModule('PaymentsEscrow', (m) => {
  const { Controller } = m.useModule(GraphPeripheryModule)
  const { PaymentsEscrowProxyAdmin, PaymentsEscrowProxy } = m.useModule(HorizonProxiesModule)

  const governor = m.getAccount(1)
  const withdrawEscrowThawingPeriod = m.getParameter('withdrawEscrowThawingPeriod')

  // Deploy PaymentsEscrow implementation - requires periphery and proxies to be registered in the controller
  const PaymentsEscrowImplementation = deployImplementation(m, {
    name: 'PaymentsEscrow',
    artifact: PaymentsEscrowArtifact,
    constructorArgs: [Controller, withdrawEscrowThawingPeriod],
  }, { after: [GraphPeripheryModule, HorizonProxiesModule] })

  // Upgrade proxy to implementation contract
  const PaymentsEscrow = upgradeTransparentUpgradeableProxyNoLoad(m,
    PaymentsEscrowProxyAdmin,
    PaymentsEscrowProxy,
    PaymentsEscrowImplementation, {
      name: 'PaymentsEscrow',
      artifact: PaymentsEscrowArtifact,
      initArgs: [],
    })

  m.call(PaymentsEscrowProxyAdmin, 'transferOwnership', [governor], { after: [PaymentsEscrow] })

  return { PaymentsEscrow, PaymentsEscrowProxyAdmin }
})

// Note that this module requires MigrateHorizonProxiesGovernorModule to be executed first
// The dependency is not made explicit to support the production workflow where the governor is a
// multisig owned by the Graph Council.
// For testnet, the dependency can be made explicit by having a parent module establish it.
export const MigratePaymentsEscrowModule = buildModule('PaymentsEscrow', (m) => {
  const { PaymentsEscrowProxyAdmin, PaymentsEscrowProxy } = m.useModule(MigrateHorizonProxiesDeployerModule)
  const { Controller } = m.useModule(MigratePeripheryModule)

  const governor = m.getAccount(1)
  const withdrawEscrowThawingPeriod = m.getParameter('withdrawEscrowThawingPeriod')

  // Deploy PaymentsEscrow implementation
  const PaymentsEscrowImplementation = deployImplementation(m, {
    name: 'PaymentsEscrow',
    artifact: PaymentsEscrowArtifact,
    constructorArgs: [Controller, withdrawEscrowThawingPeriod],
  })

  // Upgrade proxy to implementation contract
  const PaymentsEscrow = upgradeTransparentUpgradeableProxyNoLoad(m,
    PaymentsEscrowProxyAdmin,
    PaymentsEscrowProxy,
    PaymentsEscrowImplementation, {
      name: 'PaymentsEscrow',
      artifact: PaymentsEscrowArtifact,
      initArgs: [],
    })

  m.call(PaymentsEscrowProxyAdmin, 'transferOwnership', [governor], { after: [PaymentsEscrow] })

  return { PaymentsEscrow, PaymentsEscrowProxyAdmin }
})
