import { loadConfig } from '@graphprotocol/toolshed/hardhat'
import { expect } from 'chai'
import hre from 'hardhat'

import { testIf } from './lib/testIf'
import { transparentUpgradeableProxyTests } from './lib/TransparentUpgradeableProxy.tests'

const config = loadConfig(
  './ignition/configs/',
  'migrate',
  String(process.env.TEST_DEPLOYMENT_CONFIG ?? hre.network.name),
).config
const graph = hre.graph()

const addressBookEntry = graph.horizon.addressBook.getEntry('GraphPayments')
const GraphPayments = graph.horizon.contracts.GraphPayments

describe('GraphPayments', function () {
  testIf(3)('should set the right protocolPaymentCut', async function () {
    const protocolPaymentCut = await GraphPayments.PROTOCOL_PAYMENT_CUT()
    expect(protocolPaymentCut).to.equal(config.GraphPayments.protocolPaymentCut)
  })
})

transparentUpgradeableProxyTests(
  'GraphPayments',
  addressBookEntry,
  config.$global.governor as string,
  Number(process.env.TEST_DEPLOYMENT_STEP ?? 1) >= 3,
)
