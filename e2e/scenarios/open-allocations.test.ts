import { expect } from 'chai'
import hre from 'hardhat'
import { getIndexerFixtures, IndexerFixture } from './fixtures/indexers'

enum AllocationState {
  Null,
  Active,
  Closed,
  Finalized,
  Claimed,
}

let indexerFixtures: IndexerFixture[]

describe('Open allocations', () => {
  const graphOpts = {
    graphConfig: 'config/graph.goerli-scratch-5.yml',
    addressBook: 'addresses.json',
    l1GraphConfig: 'config/graph.goerli-scratch-5.yml',
    l2GraphConfig: 'config/graph.arbitrum-goerli-scratch-5.yml',
    disableSecureAccounts: true,
  }
  const { contracts, getTestAccounts } = hre.graph(graphOpts)
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
    it(`allocatons should be open`, async function () {
      const allocations = indexerFixtures.map((i) => i.allocations).flat()
      for (const allocation of allocations) {
        const state = await Staking.getAllocationState(allocation.signer.address)
        expect(state).eq(AllocationState.Active)
      }
    })
  })
})
