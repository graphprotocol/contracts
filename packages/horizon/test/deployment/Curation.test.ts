import hre from 'hardhat'

import { expect } from 'chai'
import { graphProxyTests } from './lib/GraphProxy.test'
import { loadConfig } from '@graphprotocol/toolshed/hardhat'

const config = loadConfig('./ignition/configs/', 'migrate', hre.network.name).config
const graph = hre.graph()

const graphProxyAdminAddressBookEntry = graph.horizon!.addressBook.getEntry('GraphProxyAdmin')
const curationAddressBookEntry = graph.horizon!.addressBook.getEntry('L2Curation')
const Curation = graph.horizon!.contracts.L2Curation

describe('Curation', function () {
  it('should set the right subgraph service', async function () {
    const subgraphService = await Curation.subgraphService()
    expect(subgraphService).to.equal(config.$global.subgraphServiceAddress)
  })
})

graphProxyTests('Curation', curationAddressBookEntry, graphProxyAdminAddressBookEntry.address)
