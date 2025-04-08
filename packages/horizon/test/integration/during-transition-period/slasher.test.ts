import hre from 'hardhat'

import { ethers } from 'hardhat'
import { expect } from 'chai'

import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { HorizonStakingActions } from '@graphprotocol/toolshed/actions/horizon'
import { indexers } from '../../../tasks/test/fixtures/indexers'

import type { HorizonStaking, L2GraphToken } from '@graphprotocol/toolshed/deployments/horizon'

describe('Slasher', () => {
  let horizonStaking: HorizonStaking
  let graphToken: L2GraphToken
  let snapshotId: string

  let indexer: string
  let slasher: HardhatEthersSigner
  let tokensToSlash: bigint

  before(async () => {
    const graph = hre.graph()

    horizonStaking = graph.horizon!.contracts.HorizonStaking
    graphToken = graph.horizon!.contracts.L2GraphToken

    slasher = (await ethers.getSigners())[2]
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
      await HorizonStakingActions.slash({
        horizonStaking,
        verifier: slasher,
        serviceProvider: indexer,
        tokens: tokensToSlash,
        tokensVerifier,
        verifierDestination: slasher.address,
      })

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
      await HorizonStakingActions.slash({
        horizonStaking,
        verifier: slasher,
        serviceProvider: indexer,
        tokens: tokensToSlash,
        tokensVerifier,
        verifierDestination: slasher.address,
      })

      // Indexer's entire stake should have been slashed
      const indexerStakeAfterSlash = await horizonStaking.getServiceProvider(indexer)
      expect(indexerStakeAfterSlash.tokensStaked).to.equal(0n, 'Indexer stake should have been slashed')

      // Slasher should have received the tokens
      const slasherAfterBalance = await graphToken.balanceOf(slasher.address)
      expect(slasherAfterBalance).to.equal(slasherBeforeBalance + tokensVerifier, 'Slasher should have received the tokens')
    })
  })
})
