import { expect } from 'chai'
import hre from 'hardhat'
import { Account } from '../../tasks/type-extensions'
import { fixture } from './scenario1'

describe('Scenario 1', () => {
  const {
    contracts: { GraphToken, Staking },
    getTestAccounts,
  } = hre.graph()

  let indexer1: Account
  let indexer2: Account
  let curator1: Account
  let curator2: Account
  let curator3: Account

  let indexers: Account[] = []
  let curators: Account[] = []

  before(async () => {
    ;[indexer1, indexer2, curator1, curator2, curator3] = await getTestAccounts()
    indexers = [indexer1, indexer2]
    curators = [curator1, curator2, curator3]
  })

  it('Indexer1 GRT balance should match airdropped amount', async function () {
    const balance = await GraphToken.balanceOf(indexer1.address)
    expect(balance).eq(fixture.grtAmount.sub(fixture.indexer1.stake))
  })

  it('Indexer2 GRT balance should match airdropped amount', async function () {
    const balance = await GraphToken.balanceOf(indexer2.address)
    expect(balance).eq(fixture.grtAmount.sub(fixture.indexer2.stake))
  })

  it('Curator GRT balances should match airdropped amounts', async function () {
    for (const account of curators) {
      const balance = await GraphToken.balanceOf(account.address)
      expect(balance).eq(fixture.grtAmount)
    }
  })

  it('indexer1 should have tokens staked', async function () {
    const tokensStaked = (await Staking.stakes(indexer1.address)).tokensStaked
    expect(tokensStaked).eq(fixture.indexer1.stake)
  })

  it('indexer2 should have tokens staked', async function () {
    const tokensStaked = (await Staking.stakes(indexer2.address)).tokensStaked
    expect(tokensStaked).eq(fixture.indexer2.stake)
  })
})
