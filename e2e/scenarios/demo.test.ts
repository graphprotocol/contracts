import { expect } from 'chai'
import hre from 'hardhat'
import { toGRT } from '../../cli/network'
import { Account } from '../../tasks/type-extensions'

describe('Demo scenario', () => {
  const {
    contracts: { Staking },
    getAccounts,
  } = hre.graph()

  let indexer1: Account

  before(async () => {
    ;[indexer1] = await getAccounts()
  })

  it('indexer1 should have 10_000 staked', async function () {
    const tokensStaked = (await Staking.stakes(indexer1.address)).tokensStaked
    expect(tokensStaked).eq(toGRT(10_000))
  })
})
