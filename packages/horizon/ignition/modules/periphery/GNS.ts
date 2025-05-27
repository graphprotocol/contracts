import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'
import { deployWithGraphProxy } from '../proxy/GraphProxy'

import ControllerModule from './Controller'
import CurationModule from './Curation'
import GraphProxyAdminModule from './GraphProxyAdmin'
import GraphTokenModule from './GraphToken'

import L2GNSArtifact from '@graphprotocol/contracts/build/contracts/contracts/l2/discovery/L2GNS.sol/L2GNS.json'
import SubgraphNFTArtifact from '@graphprotocol/contracts/build/contracts/contracts/discovery/SubgraphNFT.sol/SubgraphNFT.json'
import SubgraphNFTDescriptorArtifact from '@graphprotocol/contracts/build/contracts/contracts/discovery/SubgraphNFTDescriptor.sol/SubgraphNFTDescriptor.json'

// GNS deployment should be managed by ignition scripts in subgraph-service package however
// due to tight coupling with Controller it's easier to do it on the horizon package.

export default buildModule('L2GNS', (m) => {
  const { Controller } = m.useModule(ControllerModule)
  const { GraphProxyAdmin } = m.useModule(GraphProxyAdminModule)
  const { L2GraphToken } = m.useModule(GraphTokenModule)
  const { L2Curation } = m.useModule(CurationModule)

  const deployer = m.getAccount(0)
  const governor = m.getAccount(1)

  const SubgraphNFTDescriptor = m.contract('SubgraphNFTDescriptor', SubgraphNFTDescriptorArtifact)
  const SubgraphNFT = m.contract('SubgraphNFT', SubgraphNFTArtifact, [deployer])

  m.call(SubgraphNFT, 'setTokenDescriptor', [SubgraphNFTDescriptor])

  const { proxy: L2GNS, implementation: L2GNSImplementation } = deployWithGraphProxy(m, GraphProxyAdmin, {
    name: 'L2GNS',
    artifact: L2GNSArtifact,
    initArgs: [Controller, SubgraphNFT],
  })
  m.call(L2GNS, 'approveAll', [], { after: [L2GraphToken, L2Curation] })

  const setMinterCall = m.call(SubgraphNFT, 'setMinter', [L2GNS])
  m.call(SubgraphNFT, 'transferOwnership', [governor], { after: [setMinterCall] })

  return { L2GNS, L2GNSImplementation, SubgraphNFT }
})

// L2GNS and SubgraphNFT are already deployed and are not being upgraded
// This is a no-op to get the addresses into the address book
export const MigrateL2GNSModule = buildModule('L2GNS', (m) => {
  const gnsProxyAddress = m.getParameter('gnsAddress')
  const gnsImplementationAddress = m.getParameter('gnsImplementationAddress')
  const subgraphNFTAddress = m.getParameter('subgraphNFTAddress')

  const SubgraphNFT = m.contractAt('SubgraphNFT', SubgraphNFTArtifact, subgraphNFTAddress)
  const L2GNS = m.contractAt('L2GNS', L2GNSArtifact, gnsProxyAddress)
  const L2GNSImplementation = m.contractAt('L2GNSAddressBook', L2GNSArtifact, gnsImplementationAddress)

  return { L2GNS, L2GNSImplementation, SubgraphNFT }
})
