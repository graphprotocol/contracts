import { buildModule } from '@nomicfoundation/ignition-core'

import { deployWithGraphProxy } from '../proxy/GraphProxy'

import BridgeEscrowArtifact from '@graphprotocol/contracts/build/contracts/contracts/gateway/BridgeEscrow.sol/BridgeEscrow.json'
import ControllerModule from '../periphery/Controller'

export default buildModule('BridgeEscrow', (m) => {
  const { Controller } = m.useModule(ControllerModule)

  const { instance: BridgeEscrow } = deployWithGraphProxy(m, {
    name: 'BridgeEscrow',
    artifact: BridgeEscrowArtifact,
    args: [Controller],
  })

  return { BridgeEscrow }
})
