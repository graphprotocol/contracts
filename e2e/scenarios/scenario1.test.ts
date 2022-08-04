import { expect } from 'chai'
import hre from 'hardhat'
import { recreatePreviousSubgraphId } from './lib/subgraph'
import { fixture as importedFixture } from './fixtures/fixture1'
import { setFixtureSigners } from './lib/helpers'
import { BigNumber } from 'ethers'

enum AllocationState {
  Null,
  Active,
  Closed,
  Finalized,
  Claimed,
}

let fixture: any = null
describe('Scenario 1', () => {
  const { contracts } = hre.graph()
  const { GraphToken, Staking, GNS, Curation } = contracts

  before(async () => {
    fixture = await setFixtureSigners(hre, importedFixture)
  })

  describe('GRT balances', () => {
    it(`indexer balances should match airdropped amount minus staked`, async function () {
      for (const indexer of fixture.indexers) {
        const address = indexer.signer.address
        const balance = await GraphToken.balanceOf(address)
        expect(balance).eq(fixture.grtAmount.sub(indexer.stake))
      }
    })

    it(`curator balances should match airdropped amount minus signalled`, async function () {
      for (const curator of fixture.curators) {
        const address = curator.signer.address
        const balance = await GraphToken.balanceOf(address)
        expect(balance).eq(fixture.grtAmount.sub(curator.signalled))
      }
    })
  })

  describe('Staking', () => {
    it(`indexers should have staked tokens`, async function () {
      for (const indexer of fixture.indexers) {
        const address = indexer.signer.address
        const tokensStaked = (await Staking.stakes(address)).tokensStaked
        expect(tokensStaked).eq(indexer.stake)
      }
    })
  })

  describe('Subgraphs', () => {
    it(`should be published`, async function () {
      for (let i = 0; i < fixture.subgraphs.length; i++) {
        const subgraphId = await recreatePreviousSubgraphId(
          contracts,
          fixture.subgraphOwner.address,
          fixture.subgraphs.length - i,
        )
        const isPublished = await GNS.isPublished(subgraphId)
        expect(isPublished).eq(true)
      }
    })

    it(`should have signal`, async function () {
      for (let i = 0; i < fixture.subgraphs.length; i++) {
        const subgraph = fixture.subgraphs[i]
        const subgraphId = await recreatePreviousSubgraphId(
          contracts,
          fixture.subgraphOwner.address,
          fixture.subgraphs.length - i,
        )

        let totalSignal: BigNumber = BigNumber.from(0)
        for (const curator of fixture.curators) {
          const _subgraph = curator.subgraphs.find((s) => s.deploymentId === subgraph.deploymentId)
          if (_subgraph) {
            totalSignal = totalSignal.add(_subgraph.signal)
          }
        }

        const tokens = await GNS.subgraphTokens(subgraphId)
        const MAX_PPM = 1000000
        const curationTax = await Curation.curationTaxPercentage()
        const tax = totalSignal.mul(curationTax).div(MAX_PPM)
        expect(tokens).eq(totalSignal.sub(tax))
      }
    })
  })

  describe('Allocations', () => {
    it(`allocatons should be open`, async function () {
      const allocations = fixture.indexers.map((i) => i.allocations).flat()
      for (const allocation of allocations) {
        const state = await Staking.getAllocationState(allocation.signer.address)
        expect(state).eq(AllocationState.Active)
      }
    })
  })
})
