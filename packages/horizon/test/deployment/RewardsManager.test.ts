import hre from 'hardhat'

import { expect } from 'chai'
import { graphProxyTests } from './lib/GraphProxy.test'
import { IgnitionHelper } from 'hardhat-graph-protocol/sdk'

const config = IgnitionHelper.loadConfig('./ignition/configs/', 'migrate', hre.network.name).config
const graph = hre.graph()

const graphProxyAdminAddressBookEntry = graph.horizon!.addressBook.getEntry('GraphProxyAdmin')
const rewardsManagerAddressBookEntry = graph.horizon!.addressBook.getEntry('RewardsManager')
const RewardsManager = graph.horizon!.contracts.RewardsManager

describe('RewardsManager', function () {
  it('should set the right subgraph service', async function () {
    const subgraphService = await RewardsManager.subgraphService()
    expect(subgraphService).to.equal(config.$global.subgraphServiceAddress)
  })
})

graphProxyTests('RewardsManager', rewardsManagerAddressBookEntry, graphProxyAdminAddressBookEntry.address)
