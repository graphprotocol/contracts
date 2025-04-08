import { expect } from 'chai'
import hre from 'hardhat'
import { loadConfig } from '@graphprotocol/toolshed/hardhat'
import { transparentUpgradeableProxyTests } from './lib/TransparentUpgradeableProxy.tests'

const config = loadConfig('./ignition/configs/', 'migrate', hre.network.name).config
const graph = hre.graph()

const addressBookEntry = graph.horizon!.addressBook.getEntry('PaymentsEscrow')
const PaymentsEscrow = graph.horizon!.contracts.PaymentsEscrow

describe('PaymentsEscrow', function () {
  it('should set the right withdrawEscrowThawingPeriod', async function () {
    const withdrawEscrowThawingPeriod = await PaymentsEscrow.WITHDRAW_ESCROW_THAWING_PERIOD()
    expect(withdrawEscrowThawingPeriod).to.equal(config.PaymentsEscrow.withdrawEscrowThawingPeriod)
  })
})

transparentUpgradeableProxyTests('PaymentsEscrow', addressBookEntry, config.$global.governor as string)
