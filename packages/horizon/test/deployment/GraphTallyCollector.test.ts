import hre from 'hardhat'

import { expect } from 'chai'
import { loadConfig } from '@graphprotocol/toolshed/hardhat'

const config = loadConfig('./ignition/configs/', 'migrate', hre.network.name).config
const graph = hre.graph()

const GraphTallyCollector = graph.horizon.contracts.GraphTallyCollector

describe('GraphTallyCollector', function () {
  it('should set the right revokeSignerThawingPeriod', async function () {
    const revokeSignerThawingPeriod = await GraphTallyCollector.REVOKE_AUTHORIZATION_THAWING_PERIOD()
    expect(revokeSignerThawingPeriod).to.equal(config.GraphTallyCollector.revokeSignerThawingPeriod)
  })
})
