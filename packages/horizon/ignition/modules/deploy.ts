import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import type { Artifact } from '@nomicfoundation/ignition-core'

import { buildCoreModule } from './core/core'
import { buildHorizonProxiesModule } from './core/HorizonProxies'
import { buildPeripheryModule } from './periphery/periphery'

// L2Curation and L2GNS artifacts come from subgraph-service, which horizon can't depend on.
// Periphery and proxies are built once, and every module that uses them gets these same instances,
// because Ignition rejects two different modules with the same id.
export function buildHorizonModule(artifacts: { L2Curation: Artifact; L2GNS: Artifact }) {
  const GraphPeripheryModule = buildPeripheryModule(artifacts)
  const HorizonProxiesModule = buildHorizonProxiesModule(GraphPeripheryModule)
  const GraphHorizonCoreModule = buildCoreModule(GraphPeripheryModule, HorizonProxiesModule)

  return buildModule('GraphHorizon_Deploy', (m) => {
    const {
      Controller,
      EpochManager,
      EpochManagerImplementation,
      GraphProxyAdmin,
      L2GraphTokenGateway,
      L2GraphTokenGatewayImplementation,
      L2GraphToken,
      L2GraphTokenImplementation,
      RewardsManager,
      RewardsManagerImplementation,
      L2Curation,
      L2CurationImplementation,
      L2GNS,
      L2GNSImplementation,
      SubgraphNFT,
    } = m.useModule(GraphPeripheryModule)
    const {
      HorizonStaking,
      HorizonStakingImplementation,
      GraphPaymentsProxyAdmin,
      GraphPayments,
      GraphPaymentsImplementation,
      PaymentsEscrowProxyAdmin,
      PaymentsEscrow,
      PaymentsEscrowImplementation,
      GraphTallyCollector,
      RecurringCollectorProxyAdmin,
      RecurringCollector,
      RecurringCollectorImplementation,
    } = m.useModule(GraphHorizonCoreModule)

    // m.getAccount(1) rather than getParameter('governor') — the from: option on
    // m.call only accepts an AccountRuntimeValue, so the acceptOwnership signer
    // has to come from getAccount. Configs are expected to set the 'governor'
    // parameter to this same address (index 1 of the deploying mnemonic).
    const governor = m.getAccount(1)

    // BUG?: acceptOwnership should be called after everything in GraphHorizonCoreModule and GraphPeripheryModule is resolved
    // but it seems that it's not waiting for interal calls. Waiting on HorizonStaking seems to fix the issue for some reason
    // Removing HorizonStaking from the after list will trigger the bug

    // Accept ownership of Graph Governed based contracts
    m.call(Controller, 'acceptOwnership', [], {
      from: governor,
      after: [GraphPeripheryModule, GraphHorizonCoreModule, HorizonStaking],
    })
    m.call(GraphProxyAdmin, 'acceptOwnership', [], {
      from: governor,
      after: [GraphPeripheryModule, GraphHorizonCoreModule, HorizonStaking],
    })

    return {
      Controller,
      Graph_Proxy_EpochManager: EpochManager,
      Implementation_EpochManager: EpochManagerImplementation,
      Graph_Proxy_L2Curation: L2Curation,
      Implementation_L2Curation: L2CurationImplementation,
      Graph_Proxy_L2GNS: L2GNS,
      Implementation_L2GNS: L2GNSImplementation,
      SubgraphNFT,
      Graph_Proxy_RewardsManager: RewardsManager,
      Implementation_RewardsManager: RewardsManagerImplementation,
      Graph_Proxy_L2GraphTokenGateway: L2GraphTokenGateway,
      Implementation_L2GraphTokenGateway: L2GraphTokenGatewayImplementation,
      Graph_Proxy_L2GraphToken: L2GraphToken,
      Implementation_L2GraphToken: L2GraphTokenImplementation,
      GraphProxyAdmin,
      Graph_Proxy_HorizonStaking: HorizonStaking,
      Implementation_HorizonStaking: HorizonStakingImplementation,
      Transparent_ProxyAdmin_GraphPayments: GraphPaymentsProxyAdmin,
      Transparent_Proxy_GraphPayments: GraphPayments,
      Implementation_GraphPayments: GraphPaymentsImplementation,
      Transparent_ProxyAdmin_PaymentsEscrow: PaymentsEscrowProxyAdmin,
      Transparent_Proxy_PaymentsEscrow: PaymentsEscrow,
      Implementation_PaymentsEscrow: PaymentsEscrowImplementation,
      GraphTallyCollector,
      Transparent_ProxyAdmin_RecurringCollector: RecurringCollectorProxyAdmin,
      Transparent_Proxy_RecurringCollector: RecurringCollector,
      Implementation_RecurringCollector: RecurringCollectorImplementation,
    }
  })
}
