import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

import HorizonStakingArtifact from '../../../build/contracts/contracts/staking/HorizonStaking.sol/HorizonStaking.json'
import type { buildPeripheryModule } from '../periphery/periphery'
import { upgradeGraphProxy } from '../proxy/GraphProxy'
import { deployImplementation } from '../proxy/implementation'
import type { buildHorizonProxiesModule } from './HorizonProxies'

export function buildHorizonStakingModule(
  GraphPeripheryModule: ReturnType<typeof buildPeripheryModule>,
  HorizonProxiesModule: ReturnType<typeof buildHorizonProxiesModule>,
) {
  return buildModule('HorizonStaking', (m) => {
    const { Controller, GraphProxyAdmin } = m.useModule(GraphPeripheryModule)
    const { HorizonStakingProxy } = m.useModule(HorizonProxiesModule)

    const subgraphServiceAddress = m.getParameter('subgraphServiceAddress')
    const maxThawingPeriod = m.getParameter('maxThawingPeriod')

    // Deploy HorizonStaking implementation - requires periphery and proxies to be registered in the controller
    const HorizonStakingImplementation = deployImplementation(
      m,
      {
        name: 'HorizonStaking',
        artifact: HorizonStakingArtifact,
        constructorArgs: [Controller, subgraphServiceAddress],
      },
      { after: [GraphPeripheryModule, HorizonProxiesModule] },
    )

    // Upgrade proxy to implementation contract
    const HorizonStaking = upgradeGraphProxy(m, GraphProxyAdmin, HorizonStakingProxy, HorizonStakingImplementation, {
      name: 'HorizonStaking',
      artifact: HorizonStakingArtifact,
    })
    m.call(HorizonStaking, 'setMaxThawingPeriod', [maxThawingPeriod])
    m.call(HorizonStaking, 'setAllowedLockedVerifier', [subgraphServiceAddress, true])

    return { HorizonStaking, HorizonStakingImplementation }
  })
}
