import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { solidityKeccak256 } from 'ethers/lib/utils'
import hre from 'hardhat'
import { fixture } from './scenario1'

describe('Scenario 1', () => {
  const {
    contracts: { GraphToken, Staking, GNS },
    getTestAccounts,
  } = hre.graph()

  let indexer1: SignerWithAddress
  let indexer2: SignerWithAddress
  let curator1: SignerWithAddress
  let curator2: SignerWithAddress
  let curator3: SignerWithAddress
  let subgraphOwner: SignerWithAddress

  let indexers: SignerWithAddress[] = []
  let curators: SignerWithAddress[] = []

  before(async () => {
    ;[indexer1, indexer2, subgraphOwner, curator1, curator2, curator3] = await getTestAccounts()
    indexers = [indexer1, indexer2]
    curators = [curator1, curator2, curator3]
  })

  describe('GRT balances', () => {
    it('indexer1 should match airdropped amount minus staked', async function () {
      const balance = await GraphToken.balanceOf(indexer1.address)
      expect(balance).eq(fixture.grtAmount.sub(fixture.indexer1.stake))
    })

    it('indexer2 should match airdropped amount minus staked', async function () {
      const balance = await GraphToken.balanceOf(indexer2.address)
      expect(balance).eq(fixture.grtAmount.sub(fixture.indexer2.stake))
    })

    it('curator should match airdropped amount', async function () {
      for (const account of curators) {
        const balance = await GraphToken.balanceOf(account.address)
        expect(balance).eq(fixture.grtAmount)
      }
    })
  })

  describe('Staking', () => {
    it('indexer1 should have tokens staked', async function () {
      const tokensStaked = (await Staking.stakes(indexer1.address)).tokensStaked
      expect(tokensStaked).eq(fixture.indexer1.stake)
    })
    it('indexer2 should have tokens staked', async function () {
      const tokensStaked = (await Staking.stakes(indexer2.address)).tokensStaked
      expect(tokensStaked).eq(fixture.indexer2.stake)
    })
  })

  describe('Subgraphs', () => {
    for (const subgraphDeploymentId of fixture.subgraphs) {
      it(`${subgraphDeploymentId} is published`, async function () {
        const seqID = await GNS.nextAccountSeqID(subgraphOwner.address)
        const subgraphId = solidityKeccak256(['address', 'uint256'], [subgraphOwner.address, seqID])

        await GNS.subgraphs(subgraphDeploymentId)

        const isPublished = await GNS.isPublished(subgraphId)
        expect(isPublished).eq(true)
      })
    }
  })
})
