import { buildModule } from '@nomicfoundation/ignition-core'

import { deployWithGraphProxy } from '../proxy/GraphProxy'

import BridgeEscrowArtifact from '@graphprotocol/contracts/build/contracts/contracts/gateway/BridgeEscrow.sol/BridgeEscrow.json'
import ControllerModule from '../periphery/Controller'

export default buildModule('BridgeEscrow', (m) => {
  const isMigrate = m.getParameter('isMigrate', false)

  let BridgeEscrow
  if (isMigrate) {
    const bridgeEscrowProxyAddress = m.getParameter('bridgeEscrowProxyAddress')
    BridgeEscrow = m.contractAt('BridgeEscrow', BridgeEscrowArtifact, bridgeEscrowProxyAddress)
  } else {
    const { Controller } = m.useModule(ControllerModule)

    BridgeEscrow = deployWithGraphProxy(m, {
      name: 'BridgeEscrow',
      artifact: BridgeEscrowArtifact,
      args: [Controller],
    }).instance
  }

  return { BridgeEscrow }
})
