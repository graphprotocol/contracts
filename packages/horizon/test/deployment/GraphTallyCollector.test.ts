import { loadConfig } from '@graphprotocol/toolshed/hardhat'
import { expect } from 'chai'
import hre from 'hardhat'

import { testIf } from './lib/testIf'

const config = loadConfig(
  './ignition/configs/',
  'migrate',
  String(process.env.TEST_DEPLOYMENT_CONFIG ?? hre.network.name),
).config
const graph = hre.graph()

const GraphTallyCollector = graph.horizon.contracts.GraphTallyCollector

describe('GraphTallyCollector', function () {
  testIf(3)('should set the right revokeSignerThawingPeriod', async function () {
    const revokeSignerThawingPeriod = await GraphTallyCollector.REVOKE_AUTHORIZATION_THAWING_PERIOD()
    expect(revokeSignerThawingPeriod).to.equal(config.GraphTallyCollector.revokeSignerThawingPeriod)
  })
})
