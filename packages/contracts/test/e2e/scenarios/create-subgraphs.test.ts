import { expect } from 'chai'
import hre from 'hardhat'
import { recreatePreviousSubgraphId } from '@graphprotocol/sdk'
import { BigNumber } from 'ethers'
import { CuratorFixture, getCuratorFixtures } from './fixtures/curators'
import { getSubgraphFixtures, getSubgraphOwner, SubgraphFixture } from './fixtures/subgraphs'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

let curatorFixtures: CuratorFixture[]
let subgraphFixtures: SubgraphFixture[]
let subgraphOwnerFixture: SignerWithAddress

describe('Publish subgraphs', () => {
  const { contracts, getTestAccounts, chainId } = hre.graph()
  const { GNS, GraphToken, Curation } = contracts

  before(async () => {
    const testAccounts = await getTestAccounts()
    curatorFixtures = getCuratorFixtures(testAccounts)
    subgraphFixtures = getSubgraphFixtures()
    subgraphOwnerFixture = getSubgraphOwner(testAccounts).signer
  })

  describe('GRT balances', () => {
    it(`curator balances should match airdropped amount minus signalled`, async function () {
      for (const curator of curatorFixtures) {
        const address = curator.signer.address
        const balance = await GraphToken.balanceOf(address)
        expect(balance).eq(curator.grtBalance.sub(curator.signalled))
      }
    })
  })

  describe('Subgraphs', () => {
    it(`should be published`, async function () {
      for (let i = 0; i < subgraphFixtures.length; i++) {
        const subgraphId = await recreatePreviousSubgraphId(contracts, undefined, {
          owner: subgraphOwnerFixture.address,
          previousIndex: subgraphFixtures.length - i,
          chainId: chainId,
        })
        const isPublished = await GNS.isPublished(subgraphId)
        expect(isPublished).eq(true)
      }
    })

    it(`should have signal`, async function () {
      for (let i = 0; i < subgraphFixtures.length; i++) {
        const subgraph = subgraphFixtures[i]
        const subgraphId = await recreatePreviousSubgraphId(contracts, undefined, {
          owner: subgraphOwnerFixture.address,
          previousIndex: subgraphFixtures.length - i,
          chainId: chainId,
        })

        let totalSignal: BigNumber = BigNumber.from(0)
        for (const curator of curatorFixtures) {
          const _subgraph = curator.subgraphs.find(s => s.deploymentId === subgraph.deploymentId)
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
})
