import hre from 'hardhat'

import { expect } from 'chai'
import { loadConfig } from '@graphprotocol/toolshed/hardhat'
import { transparentUpgradeableProxyTests } from './lib/TransparentUpgradeableProxy.tests'

const config = loadConfig('./ignition/configs/', 'migrate', hre.network.name).config
const graph = hre.graph()

const addressBookEntry = graph.horizon.addressBook.getEntry('GraphPayments')
const GraphPayments = graph.horizon.contracts.GraphPayments

describe('GraphPayments', function () {
  it('should set the right protocolPaymentCut', async function () {
    const protocolPaymentCut = await GraphPayments.PROTOCOL_PAYMENT_CUT()
    expect(protocolPaymentCut).to.equal(config.GraphPayments.protocolPaymentCut)
  })
})

transparentUpgradeableProxyTests('GraphPayments', addressBookEntry, config.$global.governor as string)
