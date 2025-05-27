import hre from 'hardhat'

import { expect } from 'chai'
import { graphProxyTests } from './lib/GraphProxy.test'

const graph = hre.graph()

const graphProxyAdminAddressBookEntry = graph.horizon.addressBook.getEntry('GraphProxyAdmin')
const gnsAddressBookEntry = graph.horizon.addressBook.getEntry('L2GNS')
const GNS = graph.horizon.contracts.L2GNS
const SubgraphNFT = graph.horizon.contracts.SubgraphNFT

describe('GNS', function () {
  it('should set the right subgraphNFT address', async function () {
    const subgraphNFT = await GNS.subgraphNFT()
    expect(subgraphNFT).to.equal(SubgraphNFT)
  })
})

graphProxyTests('GNS', gnsAddressBookEntry, graphProxyAdminAddressBookEntry.address)
