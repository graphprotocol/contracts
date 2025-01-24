import { buildModule } from '@nomicfoundation/ignition-core'

import { deployWithGraphProxy } from '../proxy/GraphProxy'

import ControllerModule from '../periphery/Controller'
import GraphProxyAdminModule from '../periphery/GraphProxyAdmin'

import BridgeEscrowArtifact from '@graphprotocol/contracts/build/contracts/contracts/gateway/BridgeEscrow.sol/BridgeEscrow.json'

export default buildModule('BridgeEscrow', (m) => {
  const { Controller } = m.useModule(ControllerModule)
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)

  const BridgeEscrow = deployWithGraphProxy(m, GraphProxyAdmin, {
    name: 'BridgeEscrow',
    artifact: BridgeEscrowArtifact,
    initArgs: [Controller],
  })

  return { BridgeEscrow }
})
