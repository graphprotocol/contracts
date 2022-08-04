import { expect } from 'chai'
import hre from 'hardhat'
import { fixture as importedFixture } from './scenario1'
import { setFixtureSigners } from './lib/helpers'

enum AllocationState {
  Null,
  Active,
  Closed,
  Finalized,
  Claimed,
}

let fixture: any = null
describe('Scenario 1 - Part 2', () => {
  const { contracts } = hre.graph()
  const { Staking } = contracts

  before(async () => {
    fixture = await setFixtureSigners(hre, importedFixture)
  })

  describe('Allocations', () => {
    let allocations = []
    let openAllocations = []
    let closedAllocations = []

    before(async () => {
      allocations = fixture.indexers.map((i) => i.allocations).flat()
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
