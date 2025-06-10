import { SubgraphAvailabilityManager } from '@graphprotocol/contracts'
import { IRewardsManager } from '@graphprotocol/contracts'
import { deploy, DeployType, GraphNetworkContracts, randomAddress, randomHexBytes } from '@graphprotocol/sdk'
import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect } from 'chai'
import { constants } from 'ethers'
import hre from 'hardhat'
import { ethers } from 'hardhat'

import { NetworkFixture } from '../lib/fixtures'

const { AddressZero } = constants

describe('SubgraphAvailabilityManager', () => {
  const graph = hre.graph()
  let me: SignerWithAddress
  let governor: SignerWithAddress

  let oracles: string[]
  let oracleOne: SignerWithAddress
  let oracleTwo: SignerWithAddress
  let oracleThree: SignerWithAddress
  let oracleFour: SignerWithAddress
  let oracleFive: SignerWithAddress

  let newOracle: SignerWithAddress

  let fixture: NetworkFixture

  const executionThreshold = '3'
  const voteTimeLimit = '5' // 5 seconds

  let contracts: GraphNetworkContracts
  let rewardsManager: IRewardsManager
  let subgraphAvailabilityManager: SubgraphAvailabilityManager

  const subgraphDeploymentID1 = randomHexBytes()
  const subgraphDeploymentID2 = randomHexBytes()
  const subgraphDeploymentID3 = randomHexBytes()

  before(async () => {
    ;[me, oracleOne, oracleTwo, oracleThree, oracleFour, oracleFive, newOracle] = await graph.getTestAccounts()
    ;({ governor } = await graph.getNamedAccounts())

    oracles = [oracleOne.address, oracleTwo.address, oracleThree.address, oracleFour.address, oracleFive.address]

    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
    rewardsManager = contracts.RewardsManager as IRewardsManager
    const deployResult = await deploy(DeployType.Deploy, governor, {
      name: 'SubgraphAvailabilityManager',
      args: [governor.address, rewardsManager.address, executionThreshold, voteTimeLimit, oracles],
    })
    subgraphAvailabilityManager = deployResult.contract as SubgraphAvailabilityManager

    await rewardsManager.connect(governor).setSubgraphAvailabilityOracle(subgraphAvailabilityManager.address)
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('deployment', () => {
    it('should deploy', function () {
      expect(subgraphAvailabilityManager.address).to.be.properAddress
    })

    it('should revert if oracles array is less than 5', async () => {
      await expect(
        deploy(DeployType.Deploy, governor, {
          name: 'SubgraphAvailabilityManager',
          args: [
            governor.address,
            rewardsManager.address,
            executionThreshold,
            voteTimeLimit,
            [oracleOne.address, oracleTwo.address, oracleThree.address, oracleFour.address],
          ],
        }),
      ).to.be.reverted
    })

    it('should revert if an oracle is address zero', async () => {
      await expect(
        deploy(DeployType.Deploy, governor, {
          name: 'SubgraphAvailabilityManager',
          args: [
            governor.address,
            rewardsManager.address,
            executionThreshold,
            voteTimeLimit,
            [AddressZero, oracleTwo.address, oracleThree.address, oracleFour.address, oracleFive.address],
          ],
        }),
      ).to.be.revertedWith('SAM: oracle cannot be address zero')
    })

    it('should revert if governor is address zero', async () => {
      await expect(
        deploy(DeployType.Deploy, governor, {
          name: 'SubgraphAvailabilityManager',
          args: [AddressZero, rewardsManager.address, executionThreshold, voteTimeLimit, oracles],
        }),
      ).to.be.revertedWith('SAM: governor must be set')
    })

    it('should revert if rewardsManager is address zero', async () => {
      await expect(
        deploy(DeployType.Deploy, governor, {
          name: 'SubgraphAvailabilityManager',
          args: [governor.address, AddressZero, executionThreshold, voteTimeLimit, oracles],
        }),
      ).to.be.revertedWith('SAM: rewardsManager must be set')
    })

    it('should revert if executionThreshold is too low', async () => {
      await expect(
        deploy(DeployType.Deploy, governor, {
          name: 'SubgraphAvailabilityManager',
          args: [governor.address, rewardsManager.address, '2', voteTimeLimit, oracles],
        }),
      ).to.be.revertedWith('SAM: executionThreshold too low')
    })

    it('should revert if executionThreshold is too high', async () => {
      await expect(
        deploy(DeployType.Deploy, governor, {
          name: 'SubgraphAvailabilityManager',
          args: [governor.address, rewardsManager.address, '6', voteTimeLimit, oracles],
        }),
      ).to.be.revertedWith('SAM: executionThreshold too high')
    })
  })

  describe('initializer', () => {
    it('should init governor', async () => {
      expect(await subgraphAvailabilityManager.governor()).to.be.equal(governor.address)
    })

    it('should init executionThreshold', async () => {
      expect(await subgraphAvailabilityManager.executionThreshold()).to.be.equal(executionThreshold)
    })

    it('should init voteTimeLimit', async () => {
      expect(await subgraphAvailabilityManager.voteTimeLimit()).to.be.equal(voteTimeLimit)
    })

    it('should init oracles', async () => {
      for (let i = 0; i < oracles.length; i++) {
        expect(await subgraphAvailabilityManager.oracles(i)).to.be.equal(oracles[i])
      }
    })
  })

  describe('set vote limit', function () {
    it('sets voteTimeLimit successfully', async () => {
      const newVoteTimeLimit = 10
      await expect(subgraphAvailabilityManager.connect(governor).setVoteTimeLimit(newVoteTimeLimit))
        .emit(subgraphAvailabilityManager, 'VoteTimeLimitSet')
        .withArgs(newVoteTimeLimit)
      expect(await subgraphAvailabilityManager.voteTimeLimit()).to.be.equal(newVoteTimeLimit)
    })

    it('should fail if not called by governor', async () => {
      const newVoteTimeLimit = 10
      await expect(subgraphAvailabilityManager.connect(me).setVoteTimeLimit(newVoteTimeLimit)).to.be.revertedWith(
        'Only Governor can call',
      )
    })
  })

  describe('set oracles', () => {
    it('sets an oracle successfully', async () => {
      const oracle = randomAddress()
      await expect(subgraphAvailabilityManager.connect(governor).setOracle(0, oracle))
        .emit(subgraphAvailabilityManager, 'OracleSet')
        .withArgs(0, oracle)
      expect(await subgraphAvailabilityManager.oracles(0)).to.be.equal(oracle)
    })

    it('should fail if not called by governor', async () => {
      const oracle = randomAddress()
      await expect(subgraphAvailabilityManager.connect(me).setOracle(0, oracle)).to.be.revertedWith(
        'Only Governor can call',
      )
    })

    it('should fail if setting oracle to address zero', async () => {
      await expect(subgraphAvailabilityManager.connect(governor).setOracle(0, AddressZero)).to.revertedWith(
        'SAM: oracle cannot be address zero',
      )
    })

    it('should fail if index is out of bounds', async () => {
      const oracle = randomAddress()
      await expect(subgraphAvailabilityManager.connect(governor).setOracle(5, oracle)).to.be.revertedWith(
        'SAM: index out of bounds',
      )
    })
  })

  describe('voting', function () {
    it('votes denied successfully', async () => {
      const denied = true
      const tx = await subgraphAvailabilityManager.connect(oracleOne).vote(subgraphDeploymentID1, denied, 0)
      const timestamp = (await ethers.provider.getBlock('latest')).timestamp
      await expect(tx)
        .to.emit(subgraphAvailabilityManager, 'OracleVote')
        .withArgs(subgraphDeploymentID1, denied, 0, timestamp)
    })

    it('should fail if not called by oracle', async () => {
      const denied = true
      await expect(subgraphAvailabilityManager.connect(me).vote(subgraphDeploymentID1, denied, 0)).to.be.revertedWith(
        'SAM: caller must be oracle',
      )
    })

    it('should fail if index is out of bounds', async () => {
      const denied = true
      await expect(
        subgraphAvailabilityManager.connect(oracleOne).vote(subgraphDeploymentID1, denied, 5),
      ).to.be.revertedWith('SAM: index out of bounds')
    })

    it('should fail if oracle used an incorrect index', async () => {
      const denied = true
      await expect(
        subgraphAvailabilityManager.connect(oracleOne).vote(subgraphDeploymentID1, denied, 1),
      ).to.be.revertedWith('SAM: caller must be oracle')
    })

    it('should still be allowed if only one oracle has voted', async () => {
      const denied = true
      const tx = await subgraphAvailabilityManager.connect(oracleOne).vote(subgraphDeploymentID1, denied, 0)
      await expect(tx).to.emit(subgraphAvailabilityManager, 'OracleVote')
      expect(await rewardsManager.isDenied(subgraphDeploymentID1)).to.be.false
    })

    it('should be denied or allowed if majority of oracles have voted', async () => {
      // 3/5 oracles vote denied = true
      let denied = true
      await subgraphAvailabilityManager.connect(oracleOne).vote(subgraphDeploymentID1, denied, 0)
      await subgraphAvailabilityManager.connect(oracleTwo).vote(subgraphDeploymentID1, denied, 1)
      const tx = await subgraphAvailabilityManager.connect(oracleThree).vote(subgraphDeploymentID1, denied, 2)
      await expect(tx).to.emit(rewardsManager, 'RewardsDenylistUpdated').withArgs(subgraphDeploymentID1, tx.blockNumber)

      // check events order
      const receipt = await tx.wait()
      expect(receipt.events[0].event).to.be.equal('OracleVote')
      const rewardsManangerEvent = rewardsManager.interface.parseLog(receipt.logs[1]).name
      expect(rewardsManangerEvent).to.be.equal('RewardsDenylistUpdated')

      // check that subgraph is denied
      expect(await rewardsManager.isDenied(subgraphDeploymentID1)).to.be.true

      // 3/5 oracles vote denied = false
      denied = false
      await subgraphAvailabilityManager.connect(oracleOne).vote(subgraphDeploymentID1, denied, 0)
      await subgraphAvailabilityManager.connect(oracleTwo).vote(subgraphDeploymentID1, denied, 1)
      await subgraphAvailabilityManager.connect(oracleThree).vote(subgraphDeploymentID1, denied, 2)

      // check that subgraph is not denied
      expect(await rewardsManager.isDenied(subgraphDeploymentID1)).to.be.false
    })

    it('should not be denied if the same oracle votes three times', async () => {
      const denied = true
      await subgraphAvailabilityManager.connect(oracleOne).vote(subgraphDeploymentID1, denied, 0)
      await subgraphAvailabilityManager.connect(oracleOne).vote(subgraphDeploymentID1, denied, 0)
      await subgraphAvailabilityManager.connect(oracleOne).vote(subgraphDeploymentID1, denied, 0)

      expect(await rewardsManager.isDenied(subgraphDeploymentID1)).to.be.false
    })

    it('should not be denied if voteTimeLimit has passed and not enough oracles have voted', async () => {
      // 2/3 oracles vote denied = true
      const denied = true
      await subgraphAvailabilityManager.connect(oracleOne).vote(subgraphDeploymentID1, denied, 0)
      await subgraphAvailabilityManager.connect(oracleTwo).vote(subgraphDeploymentID1, denied, 1)

      // increase time by 6 seconds
      await ethers.provider.send('evm_increaseTime', [6])
      // last oracle votes denied = true
      const tx = await subgraphAvailabilityManager.connect(oracleThree).vote(subgraphDeploymentID1, denied, 2)
      await expect(tx).to.not.emit(rewardsManager, 'RewardsDenylistUpdated')

      // subgraph state didn't change because enough time has passed so that
      // previous votes are no longer valid
      expect(await rewardsManager.isDenied(subgraphDeploymentID1)).to.be.false
    })

    it('clears opposite vote when voting', async () => {
      const denied = true
      await subgraphAvailabilityManager.connect(oracleOne).vote(subgraphDeploymentID1, denied, 0)
      await subgraphAvailabilityManager.connect(oracleTwo).vote(subgraphDeploymentID1, denied, 1)
      await subgraphAvailabilityManager.connect(oracleThree).vote(subgraphDeploymentID1, denied, 2)

      // 3/5 oracles vote denied = true so subgraph is denied
      expect(await rewardsManager.isDenied(subgraphDeploymentID1)).to.be.true

      // oracleOne changes its vote to denied = false
      await subgraphAvailabilityManager.connect(oracleOne).vote(subgraphDeploymentID1, false, 0)

      // last deny vote should be 0 for oracleOne
      expect(await subgraphAvailabilityManager.lastDenyVote(0, subgraphDeploymentID1, 0)).to.be.equal(0)

      // executionThreshold isn't met now since oracleOne changed its vote
      expect(await subgraphAvailabilityManager.checkVotes(subgraphDeploymentID1, denied)).to.be.false

      // subgraph is still denied in rewards manager because only one oracle changed its vote
      expect(await rewardsManager.isDenied(subgraphDeploymentID1)).to.be.true
    })
  })

  describe('vote many', function () {
    it('votes many successfully', async () => {
      const subgraphs = [subgraphDeploymentID1, subgraphDeploymentID2, subgraphDeploymentID3]
      const denied = [true, false, true]
      const tx = await subgraphAvailabilityManager.connect(oracleOne).voteMany(subgraphs, denied, 0)
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
      await subgraphAvailabilityManager.connect(oracleOne).voteMany(subgraphs, denied, 0)
      await subgraphAvailabilityManager.connect(oracleTwo).voteMany(subgraphs, denied, 1)

      const tx = await subgraphAvailabilityManager.connect(oracleThree).voteMany(subgraphs, denied, 2)

      await expect(tx).to.emit(rewardsManager, 'RewardsDenylistUpdated').withArgs(subgraphDeploymentID1, tx.blockNumber)
      await expect(tx).to.emit(rewardsManager, 'RewardsDenylistUpdated').withArgs(subgraphDeploymentID2, 0)
      await expect(tx).to.emit(rewardsManager, 'RewardsDenylistUpdated').withArgs(subgraphDeploymentID3, tx.blockNumber)

      // check that subgraphs are denied
      expect(await rewardsManager.isDenied(subgraphDeploymentID1)).to.be.true
      expect(await rewardsManager.isDenied(subgraphDeploymentID2)).to.be.false
      expect(await rewardsManager.isDenied(subgraphDeploymentID3)).to.be.true
    })

    it('should fail if not called by oracle', async () => {
      const subgraphs = [subgraphDeploymentID1, subgraphDeploymentID2, subgraphDeploymentID3]
      const denied = [true, false, true]
      await expect(subgraphAvailabilityManager.connect(me).voteMany(subgraphs, denied, 0)).to.be.revertedWith(
        'SAM: caller must be oracle',
      )
    })

    it('should fail if index is out of bounds', async () => {
      const subgraphs = [subgraphDeploymentID1, subgraphDeploymentID2, subgraphDeploymentID3]
      const denied = [true, false, true]
      await expect(subgraphAvailabilityManager.connect(oracleOne).voteMany(subgraphs, denied, 5)).to.be.revertedWith(
        'SAM: index out of bounds',
      )
    })

    it('should fail if oracle used an incorrect index', async () => {
      const subgraphs = [subgraphDeploymentID1, subgraphDeploymentID2, subgraphDeploymentID3]
      const denied = [true, false, true]
      await expect(subgraphAvailabilityManager.connect(oracleOne).voteMany(subgraphs, denied, 1)).to.be.revertedWith(
        'SAM: caller must be oracle',
      )
    })
  })

  describe('refreshing votes', () => {
    it('should refresh votes if an oracle is replaced', async () => {
      const denied = true
      // 2/3 oracles vote denied = true
      await subgraphAvailabilityManager.connect(oracleOne).vote(subgraphDeploymentID1, denied, 0)
      await subgraphAvailabilityManager.connect(oracleTwo).vote(subgraphDeploymentID1, denied, 1)

      // replace oracleOne with a new oracle
      await subgraphAvailabilityManager.connect(governor).setOracle(2, newOracle.address)

      // new oracle votes denied = true
      await subgraphAvailabilityManager.connect(newOracle).vote(subgraphDeploymentID1, denied, 2)

      // subgraph shouldn't be denied because setting a new oracle should refresh the votes
      expect(await rewardsManager.isDenied(subgraphDeploymentID1)).to.be.false
    })

    it('should refresh votes if voteTimeLimit changes', async () => {
      const denied = true
      // 2/3 oracles vote denied = true
      await subgraphAvailabilityManager.connect(oracleOne).vote(subgraphDeploymentID1, denied, 0)
      await subgraphAvailabilityManager.connect(oracleTwo).vote(subgraphDeploymentID1, denied, 1)

      // change voteTimeLimit to 10 seconds
      await subgraphAvailabilityManager.connect(governor).setVoteTimeLimit(10)

      // last oracle votes denied = true
      await subgraphAvailabilityManager.connect(oracleThree).vote(subgraphDeploymentID1, denied, 2)

      // subgraph shouldn't be denied because voteTimeLimit should refresh the votes
      expect(await rewardsManager.isDenied(subgraphDeploymentID1)).to.be.false
    })
  })
})
