import { expect } from 'chai'
import hre from 'hardhat'
import { AllocationFixture, getIndexerFixtures, IndexerFixture } from './fixtures/indexers'

enum AllocationState {
  Null,
  Active,
  Closed,
}

let indexerFixtures: IndexerFixture[]

describe('Close allocations', () => {
  const { contracts, getTestAccounts } = hre.graph()
  const { Staking } = contracts

  before(async () => {
    indexerFixtures = getIndexerFixtures(await getTestAccounts())
  })

  describe('Allocations', () => {
    let allocations: AllocationFixture[] = []
    let openAllocations: AllocationFixture[] = []
    let closedAllocations: AllocationFixture[] = []

    before(async () => {
      allocations = indexerFixtures.map((i) => i.allocations).flat()
      openAllocations = allocations.filter((a) => !a.close)
      closedAllocations = allocations.filter((a) => a.close)
    })

    it(`some allocatons should be open`, async function () {
      for (const allocation of openAllocations) {
        const state = await Staking.getAllocationState(allocation.signer.address)
        expect(state).eq(AllocationState.Active)
      }
    })

    it(`some allocatons should be closed`, async function () {
      for (const allocation of closedAllocations) {
        const state = await Staking.getAllocationState(allocation.signer.address)
        expect(state).eq(AllocationState.Closed)
      }
    })
  })
})
