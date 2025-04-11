import hre from 'hardhat'

import { ethers } from 'hardhat'
import { expect } from 'chai'

import { indexers } from '../../../tasks/test/fixtures/indexers'

import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

describe('Slasher', () => {
  let snapshotId: string

  let indexer: string
  let slasher: HardhatEthersSigner
  let tokensToSlash: bigint

  const graph = hre.graph()
  const horizonStaking = graph.horizon.contracts.HorizonStaking
  const graphToken = graph.horizon.contracts.L2GraphToken

  before(async () => {
    slasher = await graph.accounts.getArbitrator()
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe('Available tokens', () => {
    before(() => {
      const indexerFixture = indexers[0]
      indexer = indexerFixture.address
      tokensToSlash = ethers.parseEther('10000')
    })

    it('should be able to slash indexer stake', async () => {
      // Before slash state
      const idleStakeBeforeSlash = await horizonStaking.getIdleStake(indexer)
      const tokensVerifier = tokensToSlash / 2n
      const slasherBeforeBalance = await graphToken.balanceOf(slasher.address)

      // Slash tokens
      await horizonStaking.connect(slasher).slash(indexer, tokensToSlash, tokensVerifier, slasher.address)

      // Indexer's stake should have decreased
      const idleStakeAfterSlash = await horizonStaking.getIdleStake(indexer)
      expect(idleStakeAfterSlash).to.equal(idleStakeBeforeSlash - tokensToSlash, 'Indexer stake should have decreased')

      // Slasher should have received the tokens
      const slasherAfterBalance = await graphToken.balanceOf(slasher.address)
      expect(slasherAfterBalance).to.equal(slasherBeforeBalance + tokensVerifier, 'Slasher should have received the tokens')
    })
  })

  describe('Locked tokens', () => {
    before(() => {
      const indexerFixture = indexers[1]
      indexer = indexerFixture.address
      tokensToSlash = indexerFixture.stake
    })

    it('should be able to slash locked tokens', async () => {
      // Before slash state
      const tokensVerifier = tokensToSlash / 2n
      const slasherBeforeBalance = await graphToken.balanceOf(slasher.address)

      // Slash tokens
      await horizonStaking.connect(slasher).slash(indexer, tokensToSlash, tokensVerifier, slasher.address)

      // Indexer's entire stake should have been slashed
      const indexerStakeAfterSlash = await horizonStaking.getServiceProvider(indexer)
      expect(indexerStakeAfterSlash.tokensStaked).to.equal(0n, 'Indexer stake should have been slashed')

      // Slasher should have received the tokens
      const slasherAfterBalance = await graphToken.balanceOf(slasher.address)
      expect(slasherAfterBalance).to.equal(slasherBeforeBalance + tokensVerifier, 'Slasher should have received the tokens')
    })
  })
})
