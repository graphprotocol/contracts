import { expect } from 'chai'
import hre from 'hardhat'
import { toGRT } from '../../cli/network'
import { Account } from '../../tasks/type-extensions'

describe('Airdrop scenario', () => {
  const {
    contracts: { GraphToken },
    getAccounts,
  } = hre.graph()

  let indexer1: Account

  before(async () => {
    ;[indexer1] = await getAccounts()
  })

  it('indexer1 should have at least 10_000 GRT', async function () {
    const balance = await GraphToken.balanceOf(indexer1.address)
    expect(balance).gt(toGRT(10_000))
  })
})
