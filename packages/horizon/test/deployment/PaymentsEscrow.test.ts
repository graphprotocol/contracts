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

const addressBookEntry = graph.horizon.addressBook.getEntry('PaymentsEscrow')
const PaymentsEscrow = graph.horizon.contracts.PaymentsEscrow

describe('PaymentsEscrow', function () {
  testIf(3)('should set the right withdrawEscrowThawingPeriod', async function () {
    const withdrawEscrowThawingPeriod = await PaymentsEscrow.WITHDRAW_ESCROW_THAWING_PERIOD()
    expect(withdrawEscrowThawingPeriod).to.equal(config.PaymentsEscrow.withdrawEscrowThawingPeriod)
  })
})

transparentUpgradeableProxyTests(
  'PaymentsEscrow',
  addressBookEntry,
  config.$global.governor as string,
  Number(process.env.TEST_DEPLOYMENT_STEP ?? 1) >= 3,
)
