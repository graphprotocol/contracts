import { expect } from 'chai'
import { constants } from 'ethers'

import { ethers } from 'hardhat'

import { SubgraphAvailabilityManager } from '../../build/types/SubgraphAvailabilityManager'
import { IRewardsManager } from '../../build/types/IRewardsManager'

import { NetworkFixture } from '../lib/fixtures'
import * as deployment from '../lib/deployment'
import { getAccounts, randomAddress, Account, randomHexBytes } from '../lib/testHelpers'

const { AddressZero } = constants

describe('SubgraphAvailabilityManager', () => {
  let me: Account
  let governor: Account
  let oracleOne: Account
  let oracleTwo: Account
  let oracleThree: Account

  let fixture: NetworkFixture

  const maxOracles = '5'
  const executionThreshold = '3'
  const voteTimeLimit = '5' // 5 seconds
  let rewardsManager: IRewardsManager
  let subgraphAvailabilityManager: SubgraphAvailabilityManager

  const subgraphDeploymentID1 = randomHexBytes()
  const subgraphDeploymentID2 = randomHexBytes()
  const subgraphDeploymentID3 = randomHexBytes()

  before(async () => {
    ;[me, governor, oracleOne, oracleTwo, oracleThree] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ rewardsManager } = await fixture.load(governor.signer))
    subgraphAvailabilityManager = (await deployment.deployContract(
      'SubgraphAvailabilityManager',
      governor.signer,
      governor.address,
      rewardsManager.address,
      maxOracles,
      executionThreshold,
      voteTimeLimit,
    )) as unknown as SubgraphAvailabilityManager
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('deployment', () => {
    it('should deploy', async () => {
      expect(subgraphAvailabilityManager.address).to.be.properAddress
    })

    it('should revert if governor is address zero', async () => {
      await expect(
        deployment.deployContract(
          'SubgraphAvailabilityManager',
          governor.signer,
          AddressZero,
          rewardsManager.address,
          maxOracles,
          executionThreshold,
          voteTimeLimit,
        ),
      ).to.be.revertedWith('SAM: governor must be set')
    })

    it('should revert if rewardsManager is address zero', async () => {
      await expect(
        deployment.deployContract(
          'SubgraphAvailabilityManager',
          governor.signer,
          governor.address,
          AddressZero,
          maxOracles,
          executionThreshold,
          voteTimeLimit,
        ),
      ).to.be.revertedWith('SAM: rewardsManager must be set')
    })
  })

  describe('initializer', () => {
    it('should init governor', async () => {
      expect(await subgraphAvailabilityManager.governor()).to.be.equal(governor.address)
    })

    it('should init maxOracles and executionThreshold', async () => {
      expect(await subgraphAvailabilityManager.maxOracles()).to.be.equal(maxOracles)
      expect(await subgraphAvailabilityManager.executionThreshold()).to.be.equal(executionThreshold)
    })

    it('should init oracles with address zero', async () => {
      expect(await subgraphAvailabilityManager.oracles(0)).to.be.equal(AddressZero)
      expect(await subgraphAvailabilityManager.oracles(1)).to.be.equal(AddressZero)
      expect(await subgraphAvailabilityManager.oracles(2)).to.be.equal(AddressZero)
      expect(await subgraphAvailabilityManager.oracles(3)).to.be.equal(AddressZero)
      expect(await subgraphAvailabilityManager.oracles(4)).to.be.equal(AddressZero)
      await expect(subgraphAvailabilityManager.oracles(5)).to.be.reverted
    })
  })

  describe('set vote limit', async () => {
    it('sets voteTimeLimit successfully', async () => {
      const newVoteTimeLimit = 10
      await expect(
        subgraphAvailabilityManager.connect(governor.signer).setVoteTimeLimit(newVoteTimeLimit),
      )
        .emit(subgraphAvailabilityManager, 'VoteTimeLimitSet')
        .withArgs(newVoteTimeLimit)
      expect(await subgraphAvailabilityManager.voteTimeLimit()).to.be.equal(newVoteTimeLimit)
    })

    it('should fail if not called by governor', async () => {
      const newVoteTimeLimit = 10
      await expect(
        subgraphAvailabilityManager.connect(me.signer).setVoteTimeLimit(newVoteTimeLimit),
      ).to.be.revertedWith('Only Governor can call')
    })
  })

  describe('set oracles', () => {
    it('sets an oracle successfully', async () => {
      const oracle = randomAddress()
      await expect(subgraphAvailabilityManager.connect(governor.signer).setOracle(0, oracle))
        .emit(subgraphAvailabilityManager, 'OracleSet')
        .withArgs(0, oracle)
      expect(await subgraphAvailabilityManager.oracles(0)).to.be.equal(oracle)
    })

    it('should fail if not called by governor', async () => {
      const oracle = randomAddress()
      await expect(
        subgraphAvailabilityManager.connect(me.signer).setOracle(0, oracle),
      ).to.be.revertedWith('Only Governor can call')
    })

    it('should allow setting oracle to address zero', async () => {
      await expect(subgraphAvailabilityManager.connect(governor.signer).setOracle(0, AddressZero))
        .emit(subgraphAvailabilityManager, 'OracleSet')
        .withArgs(0, AddressZero)
      expect(await subgraphAvailabilityManager.oracles(0)).to.be.equal(AddressZero)
    })

    it('should fail if index is out of bounds', async () => {
      const oracle = randomAddress()
      await expect(
        subgraphAvailabilityManager.connect(governor.signer).setOracle(5, oracle),
      ).to.be.revertedWith('SAM: index out of bounds')
    })
  })

  describe('vote denied', async () => {
    beforeEach(async () => {
      await subgraphAvailabilityManager.connect(governor.signer).setOracle(0, oracleOne.address)
      await subgraphAvailabilityManager.connect(governor.signer).setOracle(1, oracleTwo.address)
      await subgraphAvailabilityManager.connect(governor.signer).setOracle(2, oracleThree.address)
      await rewardsManager
        .connect(governor.signer)
        .setSubgraphAvailabilityOracle(subgraphAvailabilityManager.address)
    })

    it('votes denied successfully', async () => {
      const denied = true
      const tx = await subgraphAvailabilityManager
        .connect(oracleOne.signer)
        .voteDenied(subgraphDeploymentID1, denied, 0)
      const timestamp = (await ethers.provider.getBlock('latest')).timestamp
      await expect(tx)
        .to.emit(subgraphAvailabilityManager, 'OracleVote')
        .withArgs(subgraphDeploymentID1, denied, 0, timestamp)
    })

    it('should fail if not called by oracle', async () => {
      const denied = true
      await expect(
        subgraphAvailabilityManager.connect(me.signer).voteDenied(subgraphDeploymentID1, denied, 0),
      ).to.be.revertedWith('SAM: caller must be oracle')
    })

    it('should fail if index is out of bounds', async () => {
      const denied = true
      await expect(
        subgraphAvailabilityManager
          .connect(oracleOne.signer)
          .voteDenied(subgraphDeploymentID1, denied, 5),
      ).to.be.revertedWith('SAM: index out of bounds')
    })

    it('should fail if oracle used an incorrect index', async () => {
      const denied = true
      await expect(
        subgraphAvailabilityManager
          .connect(oracleOne.signer)
          .voteDenied(subgraphDeploymentID1, denied, 1),
      ).to.be.revertedWith('SAM: caller must be oracle')
    })

    it('should still be allowed if only one oracle has voted', async () => {
      const denied = true
      const tx = await subgraphAvailabilityManager
        .connect(oracleOne.signer)
        .voteDenied(subgraphDeploymentID1, denied, 0)
      await expect(tx).to.emit(subgraphAvailabilityManager, 'OracleVote')
      expect(await rewardsManager.isDenied(subgraphDeploymentID1)).to.be.false
    })

    it('should be denied or allowed if majority of oracles have voted', async () => {
      // 3/5 oracles vote denied = true
      let denied = true
      await subgraphAvailabilityManager
        .connect(oracleOne.signer)
        .voteDenied(subgraphDeploymentID1, denied, 0)
      await subgraphAvailabilityManager
        .connect(oracleTwo.signer)
        .voteDenied(subgraphDeploymentID1, denied, 1)
      const tx = await subgraphAvailabilityManager
        .connect(oracleThree.signer)
        .voteDenied(subgraphDeploymentID1, denied, 2)
      await expect(tx)
        .to.emit(rewardsManager, 'RewardsDenylistUpdated')
        .withArgs(subgraphDeploymentID1, tx.blockNumber)

      // check that subgraph is denied
      expect(await rewardsManager.isDenied(subgraphDeploymentID1)).to.be.true

      // 3/5 oracles vote denied = false
      denied = false
      await subgraphAvailabilityManager
        .connect(oracleOne.signer)
        .voteDenied(subgraphDeploymentID1, denied, 0)
      await subgraphAvailabilityManager
        .connect(oracleTwo.signer)
        .voteDenied(subgraphDeploymentID1, denied, 1)
      await subgraphAvailabilityManager
        .connect(oracleThree.signer)
        .voteDenied(subgraphDeploymentID1, denied, 2)

      // check that subgraph is not denied
      expect(await rewardsManager.isDenied(subgraphDeploymentID1)).to.be.false
    })

    it('should not be denied if the same oracle votes three times', async () => {
      const denied = true
      await subgraphAvailabilityManager
        .connect(oracleOne.signer)
        .voteDenied(subgraphDeploymentID1, denied, 0)
      await subgraphAvailabilityManager
        .connect(oracleOne.signer)
        .voteDenied(subgraphDeploymentID1, denied, 0)
      await subgraphAvailabilityManager
        .connect(oracleOne.signer)
        .voteDenied(subgraphDeploymentID1, denied, 0)

      expect(await rewardsManager.isDenied(subgraphDeploymentID1)).to.be.false
    })

    it('should not be denied if voteTimeLimit has passed and not enough oracles have voted', async () => {
      // 2/3 oracles vote denied = true
      const denied = true
      await subgraphAvailabilityManager
        .connect(oracleOne.signer)
        .voteDenied(subgraphDeploymentID1, denied, 0)
      await subgraphAvailabilityManager
        .connect(oracleTwo.signer)
        .voteDenied(subgraphDeploymentID1, denied, 1)

      // increase time by 6 seconds
      await ethers.provider.send('evm_increaseTime', [6])
      // last oracle votes denied = true
      const tx = await subgraphAvailabilityManager
        .connect(oracleThree.signer)
        .voteDenied(subgraphDeploymentID1, denied, 2)
      await expect(tx).to.not.emit(rewardsManager, 'RewardsDenylistUpdated')

      // subgraph state didn't change because enough time has passed so that
      // previous votes are no longer valid
      expect(await rewardsManager.isDenied(subgraphDeploymentID1)).to.be.false
    })
  })

  describe('vote many', async () => {
    beforeEach(async () => {
      await subgraphAvailabilityManager.connect(governor.signer).setOracle(0, oracleOne.address)
      await subgraphAvailabilityManager.connect(governor.signer).setOracle(1, oracleTwo.address)
      await subgraphAvailabilityManager.connect(governor.signer).setOracle(2, oracleThree.address)
      await rewardsManager
        .connect(governor.signer)
        .setSubgraphAvailabilityOracle(subgraphAvailabilityManager.address)
    })

    it('votes many successfully', async () => {
      const subgraphs = [subgraphDeploymentID1, subgraphDeploymentID2, subgraphDeploymentID3]
      const denied = [true, false, true]
      const tx = await subgraphAvailabilityManager
        .connect(oracleOne.signer)
        .voteDeniedMany(subgraphs, denied, 0)
      const timestamp = (await ethers.provider.getBlock('latest')).timestamp
      await expect(tx)
        .to.emit(subgraphAvailabilityManager, 'OracleVote')
        .withArgs(subgraphDeploymentID1, true, 0, timestamp)
      await expect(tx)
        .to.emit(subgraphAvailabilityManager, 'OracleVote')
        .withArgs(subgraphDeploymentID2, false, 0, timestamp)
      await expect(tx)
        .to.emit(subgraphAvailabilityManager, 'OracleVote')
        .withArgs(subgraphDeploymentID3, true, 0, timestamp)
    })

    it('should change subgraph state if majority of oracles have voted', async () => {
      const subgraphs = [subgraphDeploymentID1, subgraphDeploymentID2, subgraphDeploymentID3]
      const denied = [true, false, true]
      // 3/5 oracles vote denied = true
      await subgraphAvailabilityManager
        .connect(oracleOne.signer)
        .voteDeniedMany(subgraphs, denied, 0)
      await subgraphAvailabilityManager
        .connect(oracleTwo.signer)
        .voteDeniedMany(subgraphs, denied, 1)

      const tx = await subgraphAvailabilityManager
        .connect(oracleThree.signer)
        .voteDeniedMany(subgraphs, denied, 2)

      await expect(tx)
        .to.emit(rewardsManager, 'RewardsDenylistUpdated')
        .withArgs(subgraphDeploymentID1, tx.blockNumber)
      await expect(tx)
        .to.emit(rewardsManager, 'RewardsDenylistUpdated')
        .withArgs(subgraphDeploymentID2, 0)
      await expect(tx)
        .to.emit(rewardsManager, 'RewardsDenylistUpdated')
        .withArgs(subgraphDeploymentID3, tx.blockNumber)

      // check that subgraphs are denied
      expect(await rewardsManager.isDenied(subgraphDeploymentID1)).to.be.true
      expect(await rewardsManager.isDenied(subgraphDeploymentID2)).to.be.false
      expect(await rewardsManager.isDenied(subgraphDeploymentID3)).to.be.true
    })

    it('should fail if not called by oracle', async () => {
      const subgraphs = [subgraphDeploymentID1, subgraphDeploymentID2, subgraphDeploymentID3]
      const denied = [true, false, true]
      await expect(
        subgraphAvailabilityManager.connect(me.signer).voteDeniedMany(subgraphs, denied, 0),
      ).to.be.revertedWith('SAM: caller must be oracle')
    })

    it('should fail if index is out of bounds', async () => {
      const subgraphs = [subgraphDeploymentID1, subgraphDeploymentID2, subgraphDeploymentID3]
      const denied = [true, false, true]
      await expect(
        subgraphAvailabilityManager.connect(oracleOne.signer).voteDeniedMany(subgraphs, denied, 5),
      ).to.be.revertedWith('SAM: index out of bounds')
    })

    it('should fail if oracle used an incorrect index', async () => {
      const subgraphs = [subgraphDeploymentID1, subgraphDeploymentID2, subgraphDeploymentID3]
      const denied = [true, false, true]
      await expect(
        subgraphAvailabilityManager.connect(oracleOne.signer).voteDeniedMany(subgraphs, denied, 1),
      ).to.be.revertedWith('SAM: caller must be oracle')
    })
  })
})
