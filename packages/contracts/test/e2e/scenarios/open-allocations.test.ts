import { expect } from 'chai'
import hre from 'hardhat'
import { AllocationState } from '@graphprotocol/sdk'

import { getIndexerFixtures, IndexerFixture } from './fixtures/indexers'

let indexerFixtures: IndexerFixture[]

describe('Open allocations', () => {
  const { contracts, getTestAccounts } = hre.graph()
  const { GraphToken, Staking } = contracts

  before(async () => {
    indexerFixtures = getIndexerFixtures(await getTestAccounts())
  })

  describe('GRT balances', () => {
    it(`indexer balances should match airdropped amount minus staked`, async function () {
      for (const indexer of indexerFixtures) {
        const address = indexer.signer.address
        const balance = await GraphToken.balanceOf(address)
        expect(balance).eq(indexer.grtBalance.sub(indexer.stake))
      }
    })
  })

  describe('Staking', () => {
    it(`indexers should have staked tokens`, async function () {
      for (const indexer of indexerFixtures) {
        const address = indexer.signer.address
        const tokensStaked = (await Staking.stakes(address)).tokensStaked
        expect(tokensStaked).eq(indexer.stake)
      }
    })
  })

  describe('Allocations', () => {
    it(`allocations should be open`, async function () {
      const allocations = indexerFixtures.map(i => i.allocations).flat()
      for (const allocation of allocations) {
        const state = await Staking.getAllocationState(allocation.signer.address)
        expect(state).eq(AllocationState.Active)
      }
    })
  })
})
