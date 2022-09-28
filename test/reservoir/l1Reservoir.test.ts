import { expect } from 'chai'
import { BigNumber, constants } from 'ethers'

import { defaults, deployContract, deployL1Reservoir } from '../lib/deployment'
import { ArbitrumL1Mocks, L1FixtureContracts, NetworkFixture } from '../lib/fixtures'

import { GraphToken } from '../../build/types/GraphToken'
import { ReservoirMock } from '../../build/types/ReservoirMock'
import { BigNumber as BN } from 'bignumber.js'

import {
  advanceBlocks,
  getAccounts,
  latestBlock,
  toBN,
  toGRT,
  formatGRT,
  Account,
  RewardsTracker,
} from '../lib/testHelpers'
import { L1Reservoir } from '../../build/types/L1Reservoir'
import { BridgeEscrow } from '../../build/types/BridgeEscrow'

import path from 'path'
import { Artifacts } from 'hardhat/internal/artifacts'
import { defaultAbiCoder, Interface } from 'ethers/lib/utils'
import { L1GraphTokenGateway } from '../../build/types/L1GraphTokenGateway'
import { Controller } from '../../build/types/Controller'
import { GraphProxyAdmin } from '../../build/types/GraphProxyAdmin'
import { Staking } from '../../build/types/Staking'

const { AddressZero } = constants
const toRound = (n: BigNumber) => formatGRT(n.add(toGRT('0.5'))).split('.')[0]

const maxGas = toBN('1000000')
const maxSubmissionCost = toBN('7')
const gasPriceBid = toBN('2')
const defaultEthValue = maxSubmissionCost.add(maxGas.mul(gasPriceBid))

describe('L1Reservoir', () => {
  let governor: Account
  let testAccount1: Account
  let testAccount2: Account
  let testAccount3: Account
  let mockRouter: Account
  let mockL2GRT: Account
  let mockL2Gateway: Account
  let mockL2Reservoir: Account
  let keeper: Account
  let fixture: NetworkFixture

  let grt: GraphToken
  let reservoirMock: ReservoirMock
  let l1Reservoir: L1Reservoir
  let bridgeEscrow: BridgeEscrow
  let l1GraphTokenGateway: L1GraphTokenGateway
  let controller: Controller
  let proxyAdmin: GraphProxyAdmin
  let staking: Staking

  let supplyBeforeDrip: BigNumber
  let dripBlock: BigNumber
  let fixtureContracts: L1FixtureContracts
  let arbitrumMocks: ArbitrumL1Mocks

  const ISSUANCE_RATE_PERIODS = toBN(4) // blocks required to issue 0.05% rewards
  const ISSUANCE_RATE_PER_BLOCK = toBN('1000122722344290393') // % increase every block

  // Test accumulated rewards after nBlocksToAdvance,
  // asking for the value at blockToQuery
  const shouldGetNewRewards = async (
    initialSupply: BigNumber,
    nBlocksToAdvance: BigNumber = ISSUANCE_RATE_PERIODS,
    blockToQuery?: BigNumber,
    expectedValue?: BigNumber,
    round = true,
  ) => {
    // -- t0 --
    const tracker = await RewardsTracker.create(initialSupply, ISSUANCE_RATE_PER_BLOCK)
    const startAccrued = await l1Reservoir.getAccumulatedRewards(await latestBlock())
    // Jump
    await advanceBlocks(nBlocksToAdvance)

    // -- t1 --

    // Contract calculation
    if (!blockToQuery) {
      blockToQuery = await latestBlock()
    }
    const contractAccrued = await l1Reservoir.getAccumulatedRewards(blockToQuery)
    // Local calculation
    if (expectedValue == null) {
      expectedValue = await tracker.newRewards(blockToQuery)
    }

    // Check
    if (round) {
      expect(toRound(contractAccrued.sub(startAccrued))).eq(toRound(expectedValue))
    } else {
      expect(contractAccrued.sub(startAccrued)).eq(expectedValue)
    }

    return expectedValue
  }

  const sequentialDoubleDrip = async (
    blocksToAdvance: BigNumber,
    dripInterval = defaults.rewards.dripInterval,
  ) => {
    const supplyBeforeDrip = await grt.totalSupply()
    const startAccrued = await l1Reservoir.getAccumulatedRewards(await latestBlock())
    expect(startAccrued).to.eq(0)
    const dripBlock = (await latestBlock()).add(1) // We're gonna drip in the next transaction
    const tracker = await RewardsTracker.create(
      supplyBeforeDrip,
      defaults.rewards.issuanceRate,
      dripBlock,
    )
    expect(await tracker.accRewards(dripBlock)).to.eq(0)
    let expectedNextDeadline = dripBlock.add(dripInterval)
    let expectedMintedAmount = await tracker.accRewards(expectedNextDeadline)
    const tx1 = await l1Reservoir
      .connect(keeper.signer)
      ['drip(uint256,uint256,uint256,address)'](toBN(0), toBN(0), toBN(0), keeper.address)
    const actualAmount = await grt.balanceOf(l1Reservoir.address)
    expect(await latestBlock()).eq(dripBlock)
    expect(toRound(actualAmount)).to.eq(toRound(expectedMintedAmount))
    expect(await l1Reservoir.issuanceBase()).to.eq(supplyBeforeDrip)
    await expect(tx1)
      .emit(l1Reservoir, 'RewardsDripped')
      .withArgs(actualAmount, toBN(0), expectedNextDeadline)
    await expect(tx1).emit(grt, 'Transfer').withArgs(AddressZero, l1Reservoir.address, actualAmount)
    await tracker.snapshotRewards()

    await advanceBlocks(blocksToAdvance)

    const tx2 = await l1Reservoir
      .connect(keeper.signer)
      ['drip(uint256,uint256,uint256,address)'](toBN(0), toBN(0), toBN(0), keeper.address)
    const newAmount = (await grt.balanceOf(l1Reservoir.address)).sub(actualAmount)
    expectedNextDeadline = (await latestBlock()).add(dripInterval)
    const expectedSnapshottedSupply = supplyBeforeDrip.add(await tracker.accRewards())
    expectedMintedAmount = (await tracker.accRewards(expectedNextDeadline)).sub(actualAmount)
    expect(toRound(newAmount)).to.eq(toRound(expectedMintedAmount))
    expect(toRound(await l1Reservoir.issuanceBase())).to.eq(toRound(expectedSnapshottedSupply))
    await expect(tx2)
      .emit(l1Reservoir, 'RewardsDripped')
      .withArgs(newAmount, toBN(0), expectedNextDeadline)
    await expect(tx2).emit(grt, 'Transfer').withArgs(AddressZero, l1Reservoir.address, newAmount)
  }

  before(async function () {
    ;[
      governor,
      testAccount1,
      mockRouter,
      mockL2GRT,
      mockL2Gateway,
      mockL2Reservoir,
      keeper,
      testAccount2,
      testAccount3,
    ] = await getAccounts()

    fixture = new NetworkFixture()
    fixtureContracts = await fixture.load(governor.signer)
    ;({ grt, l1Reservoir, bridgeEscrow, l1GraphTokenGateway, controller, proxyAdmin, staking } =
      fixtureContracts)

    await l1Reservoir.connect(governor.signer).initialSnapshot(toBN(0))
    arbitrumMocks = await fixture.loadArbitrumL1Mocks(governor.signer)
    await fixture.configureL1Bridge(
      governor.signer,
      arbitrumMocks,
      fixtureContracts,
      mockRouter.address,
      mockL2GRT.address,
      mockL2Gateway.address,
      mockL2Reservoir.address,
    )
    await l1Reservoir.connect(governor.signer).grantDripPermission(keeper.address)
    reservoirMock = (await deployContract(
      'ReservoirMock',
      governor.signer,
    )) as unknown as ReservoirMock
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('configuration', function () {
    describe('initial snapshot', function () {
      let reservoir: L1Reservoir
      beforeEach(async function () {
        // Deploy a new reservoir to avoid issues with initialSnapshot being called twice
        reservoir = await deployL1Reservoir(governor.signer, controller.address, proxyAdmin)
        await grt.connect(governor.signer).addMinter(reservoir.address)
      })

      it('rejects call if unauthorized', async function () {
        const tx = reservoir.connect(testAccount1.signer).initialSnapshot(toGRT('1.025'))
        await expect(tx).revertedWith('Caller must be Controller governor')
      })

      it('snapshots the total GRT supply', async function () {
        const tx = reservoir.connect(governor.signer).initialSnapshot(toGRT('0'))
        const supply = await grt.totalSupply()
        await expect(tx)
          .emit(reservoir, 'InitialSnapshotTaken')
          .withArgs(await latestBlock(), supply, toGRT('0'))
        expect(await grt.balanceOf(reservoir.address)).to.eq(toGRT('0'))
        expect(await reservoir.issuanceBase()).to.eq(supply)
        expect(await reservoir.lastRewardsUpdateBlock()).to.eq(await latestBlock())
      })
      it('mints pending rewards and includes them in the snapshot', async function () {
        const pending = toGRT('10000000')
        const tx = reservoir.connect(governor.signer).initialSnapshot(pending)
        const supply = await grt.totalSupply()
        const expectedSupply = supply.add(pending)
        await expect(tx)
          .emit(reservoir, 'InitialSnapshotTaken')
          .withArgs(await latestBlock(), expectedSupply, pending)
        expect(await grt.balanceOf(reservoir.address)).to.eq(pending)
        expect(await reservoir.issuanceBase()).to.eq(expectedSupply)
        expect(await reservoir.lastRewardsUpdateBlock()).to.eq(await latestBlock())
      })
      it('cannot be called more than once', async function () {
        let tx = reservoir.connect(governor.signer).initialSnapshot(toGRT('0'))
        await expect(tx).emit(reservoir, 'InitialSnapshotTaken')
        tx = reservoir.connect(governor.signer).initialSnapshot(toGRT('0'))
        await expect(tx).revertedWith('Cannot call this function more than once')
      })
    })
    describe('issuance rate update', function () {
      it('rejects setting issuance rate if unauthorized', async function () {
        const tx = l1Reservoir.connect(testAccount1.signer).setIssuanceRate(toGRT('1.025'))
        await expect(tx).revertedWith('Caller must be Controller governor')
      })

      it('rejects setting issuance rate to less than minimum allowed', async function () {
        const newIssuanceRate = toGRT('0.1') // this get a bignumber with 1e17
        const tx = l1Reservoir.connect(governor.signer).setIssuanceRate(newIssuanceRate)
        await expect(tx).revertedWith('Issuance rate under minimum allowed')
      })

      it('should set issuance rate to minimum allowed', async function () {
        const newIssuanceRate = toGRT('1') // this get a bignumber with 1e18
        const tx = l1Reservoir.connect(governor.signer).setIssuanceRate(newIssuanceRate)
        await expect(tx).emit(l1Reservoir, 'IssuanceRateStaged').withArgs(newIssuanceRate)
        expect(await l1Reservoir.nextIssuanceRate()).eq(newIssuanceRate)
      })

      it('should set issuance rate to apply on next drip', async function () {
        const newIssuanceRate = toGRT('1.00025')
        let tx = l1Reservoir.connect(governor.signer).setIssuanceRate(newIssuanceRate)
        await expect(tx).emit(l1Reservoir, 'IssuanceRateStaged').withArgs(newIssuanceRate)
        expect(await l1Reservoir.issuanceRate()).eq(0)
        expect(await l1Reservoir.nextIssuanceRate()).eq(newIssuanceRate)
        tx = l1Reservoir
          .connect(keeper.signer)
          ['drip(uint256,uint256,uint256,address)'](toBN(0), toBN(0), toBN(0), keeper.address)
        await expect(tx).emit(l1Reservoir, 'IssuanceRateUpdated').withArgs(newIssuanceRate)
        expect(await l1Reservoir.issuanceRate()).eq(newIssuanceRate)
      })
    })
    describe('drip interval update', function () {
      it('rejects setting drip interval if unauthorized', async function () {
        const tx = l1Reservoir.connect(testAccount1.signer).setDripInterval(toBN(40800))
        await expect(tx).revertedWith('Caller must be Controller governor')
      })

      it('rejects setting drip interval to zero', async function () {
        const tx = l1Reservoir.connect(governor.signer).setDripInterval(toBN(0))
        await expect(tx).revertedWith('Drip interval must be > 0')
      })

      it('updates the drip interval', async function () {
        const newInterval = toBN(40800)
        const tx = l1Reservoir.connect(governor.signer).setDripInterval(newInterval)
        await expect(tx).emit(l1Reservoir, 'DripIntervalUpdated').withArgs(newInterval)
        expect(await l1Reservoir.dripInterval()).eq(newInterval)
      })
    })
    describe('L2 reservoir address update', function () {
      it('rejects setting L2 reservoir address if unauthorized', async function () {
        const tx = l1Reservoir
          .connect(testAccount1.signer)
          .setL2ReservoirAddress(testAccount1.address)
        await expect(tx).revertedWith('Caller must be Controller governor')
      })

      it('updates the L2 reservoir address', async function () {
        const tx = l1Reservoir.connect(governor.signer).setL2ReservoirAddress(testAccount1.address)
        await expect(tx)
          .emit(l1Reservoir, 'L2ReservoirAddressUpdated')
          .withArgs(testAccount1.address)
        expect(await l1Reservoir.l2ReservoirAddress()).eq(testAccount1.address)
      })
    })
    describe('L2 rewards fraction update', function () {
      it('rejects setting L2 rewards fraction if unauthorized', async function () {
        const tx = l1Reservoir.connect(testAccount1.signer).setL2RewardsFraction(toGRT('1.025'))
        await expect(tx).revertedWith('Caller must be Controller governor')
      })

      it('rejects setting L2 rewards fraction to more than 1', async function () {
        const newValue = toGRT('1').add(1)
        const tx = l1Reservoir.connect(governor.signer).setL2RewardsFraction(newValue)
        await expect(tx).revertedWith('L2 Rewards fraction must be <= 1')
      })

      it('should set L2 rewards fraction to maximum allowed', async function () {
        const newValue = toGRT('1') // this gets a bignumber with 1e18
        const tx = l1Reservoir.connect(governor.signer).setL2RewardsFraction(newValue)
        await expect(tx).emit(l1Reservoir, 'L2RewardsFractionStaged').withArgs(newValue)
        expect(await l1Reservoir.l2RewardsFraction()).eq(0)
        expect(await l1Reservoir.nextL2RewardsFraction()).eq(newValue)
      })

      it('should set L2 rewards fraction to apply on next drip', async function () {
        const newValue = toGRT('0.25')
        let tx = l1Reservoir.connect(governor.signer).setL2RewardsFraction(newValue)
        await expect(tx).emit(l1Reservoir, 'L2RewardsFractionStaged').withArgs(newValue)
        expect(await l1Reservoir.nextL2RewardsFraction()).eq(newValue)
        tx = l1Reservoir
          .connect(keeper.signer)
          ['drip(uint256,uint256,uint256,address)'](
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            keeper.address,
            { value: defaultEthValue },
          )
        await expect(tx).emit(l1Reservoir, 'L2RewardsFractionUpdated').withArgs(newValue)
        expect(await l1Reservoir.l2RewardsFraction()).eq(newValue)
      })
    })
    describe('minimum drip interval update', function () {
      it('rejects setting minimum drip interval if unauthorized', async function () {
        const tx = l1Reservoir.connect(testAccount1.signer).setMinDripInterval(toBN('200'))
        await expect(tx).revertedWith('Caller must be Controller governor')
      })
      it('rejects setting minimum drip interval if equal to dripInterval', async function () {
        const tx = l1Reservoir
          .connect(governor.signer)
          .setMinDripInterval(await l1Reservoir.dripInterval())
        await expect(tx).revertedWith('MUST_BE_LT_DRIP_INTERVAL')
      })
      it('rejects setting minimum drip interval if larger than dripInterval', async function () {
        const tx = l1Reservoir
          .connect(governor.signer)
          .setMinDripInterval((await l1Reservoir.dripInterval()).add(1))
        await expect(tx).revertedWith('MUST_BE_LT_DRIP_INTERVAL')
      })
      it('sets the minimum drip interval', async function () {
        const newValue = toBN('200')
        const tx = l1Reservoir.connect(governor.signer).setMinDripInterval(newValue)
        await expect(tx).emit(l1Reservoir, 'MinDripIntervalUpdated').withArgs(newValue)
        expect(await l1Reservoir.minDripInterval()).eq(newValue)
      })
    })
    describe('allowed drippers whitelist', function () {
      it('only allows the governor to add a dripper', async function () {
        const tx = l1Reservoir
          .connect(testAccount1.signer)
          .grantDripPermission(testAccount1.address)
        await expect(tx).revertedWith('Caller must be Controller governor')
      })
      it('only allows the governor to revoke a dripper', async function () {
        const tx = l1Reservoir.connect(testAccount1.signer).revokeDripPermission(keeper.address)
        await expect(tx).revertedWith('Caller must be Controller governor')
      })
      it('allows adding an address to the allowed drippers', async function () {
        const tx = l1Reservoir.connect(governor.signer).grantDripPermission(testAccount1.address)
        await expect(tx).emit(l1Reservoir, 'AllowedDripperAdded').withArgs(testAccount1.address)
        expect(await l1Reservoir.allowedDrippers(testAccount1.address)).eq(true)
      })
      it('allows removing an address from the allowed drippers', async function () {
        await l1Reservoir.connect(governor.signer).grantDripPermission(testAccount1.address)
        const tx = l1Reservoir.connect(governor.signer).revokeDripPermission(testAccount1.address)
        await expect(tx).emit(l1Reservoir, 'AllowedDripperRevoked').withArgs(testAccount1.address)
        expect(await l1Reservoir.allowedDrippers(testAccount1.address)).eq(false)
      })
    })
  })

  // TODO test that rewardsManager.updateAccRewardsPerSignal is called when
  // issuanceRate or l2RewardsFraction is updated
  describe('drip', function () {
    it('cannot be called by an unauthorized address', async function () {
      const tx = l1Reservoir
        .connect(testAccount1.signer)
        ['drip(uint256,uint256,uint256,address)'](toBN(0), toBN(0), toBN(0), testAccount1.address)
      await expect(tx).revertedWith('UNAUTHORIZED')
    })
    it('can be called by an indexer', async function () {
      const stakedAmount = toGRT('100000')
      await grt.connect(governor.signer).mint(testAccount1.address, stakedAmount)
      await grt.connect(testAccount1.signer).approve(staking.address, stakedAmount)
      await staking.connect(testAccount1.signer).stake(stakedAmount)
      const tx = l1Reservoir
        .connect(testAccount1.signer)
        ['drip(uint256,uint256,uint256,address)'](toBN(0), toBN(0), toBN(0), testAccount1.address)
      await expect(tx).emit(l1Reservoir, 'RewardsDripped')
    })
    it('can be called by a whitelisted address', async function () {
      await l1Reservoir.connect(governor.signer).grantDripPermission(testAccount1.address)
      const tx = l1Reservoir
        .connect(testAccount1.signer)
        ['drip(uint256,uint256,uint256,address)'](toBN(0), toBN(0), toBN(0), testAccount1.address)
      await expect(tx).emit(l1Reservoir, 'RewardsDripped')
    })
    it('cannot be called with a zero address for the keeper reward beneficiary', async function () {
      await l1Reservoir.connect(governor.signer).grantDripPermission(testAccount1.address)
      const tx = l1Reservoir
        .connect(testAccount1.signer)
        ['drip(uint256,uint256,uint256,address)'](toBN(0), toBN(0), toBN(0), constants.AddressZero)
      await expect(tx).revertedWith('INVALID_BENEFICIARY')
    })
    it('(operator variant) cannot be called with an invalid indexer', async function () {
      const tx = l1Reservoir
        .connect(testAccount2.signer)
        ['drip(uint256,uint256,uint256,address,address)'](
          toBN(0),
          toBN(0),
          toBN(0),
          testAccount1.address,
          testAccount1.address,
        )
      await expect(tx).revertedWith('UNAUTHORIZED_INVALID_INDEXER')
    })
    it('(operator variant) cannot be called by someone who is not an operator for the right indexer', async function () {
      const stakedAmount = toGRT('100000')
      // testAccount1 is a valid indexer
      await grt.connect(governor.signer).mint(testAccount1.address, stakedAmount)
      await grt.connect(testAccount1.signer).approve(staking.address, stakedAmount)
      await staking.connect(testAccount1.signer).stake(stakedAmount)
      // testAccount2 is an operator for testAccount1's indexer
      await staking.connect(testAccount1.signer).setOperator(testAccount2.address, true)
      // testAccount3 is another valid indexer
      await grt.connect(governor.signer).mint(testAccount3.address, stakedAmount)
      await grt.connect(testAccount3.signer).approve(staking.address, stakedAmount)
      await staking.connect(testAccount3.signer).stake(stakedAmount)
      // But testAccount2 is not an operator for testAccount3's indexer
      const tx = l1Reservoir
        .connect(testAccount2.signer)
        ['drip(uint256,uint256,uint256,address,address)'](
          toBN(0),
          toBN(0),
          toBN(0),
          testAccount1.address,
          testAccount3.address,
        )
      await expect(tx).revertedWith('UNAUTHORIZED_INVALID_OPERATOR')
    })
    it('(operator variant) can be called by an indexer operator using an extra parameter', async function () {
      const stakedAmount = toGRT('100000')
      await grt.connect(governor.signer).mint(testAccount1.address, stakedAmount)
      await grt.connect(testAccount1.signer).approve(staking.address, stakedAmount)
      await staking.connect(testAccount1.signer).stake(stakedAmount)
      await staking.connect(testAccount1.signer).setOperator(testAccount2.address, true)
      const tx = l1Reservoir
        .connect(testAccount2.signer)
        ['drip(uint256,uint256,uint256,address,address)'](
          toBN(0),
          toBN(0),
          toBN(0),
          testAccount1.address,
          testAccount1.address,
        )
      await expect(tx).emit(l1Reservoir, 'RewardsDripped')
    })
    it('mints rewards for the next week', async function () {
      supplyBeforeDrip = await grt.totalSupply()
      const startAccrued = await l1Reservoir.getAccumulatedRewards(await latestBlock())
      expect(startAccrued).to.eq(0)
      const dripBlock = (await latestBlock()).add(1) // We're gonna drip in the next transaction
      const tracker = await RewardsTracker.create(
        supplyBeforeDrip,
        defaults.rewards.issuanceRate,
        dripBlock,
      )
      expect(await tracker.accRewards(dripBlock)).to.eq(0)
      const expectedNextDeadline = dripBlock.add(defaults.rewards.dripInterval)
      const expectedMintedAmount = await tracker.accRewards(expectedNextDeadline)
      const tx = await l1Reservoir
        .connect(keeper.signer)
        ['drip(uint256,uint256,uint256,address)'](toBN(0), toBN(0), toBN(0), keeper.address)
      const actualAmount = await grt.balanceOf(l1Reservoir.address)
      expect(toRound(actualAmount)).to.eq(toRound(expectedMintedAmount))
      expect(await l1Reservoir.issuanceBase()).to.eq(supplyBeforeDrip)
      await expect(tx)
        .emit(l1Reservoir, 'RewardsDripped')
        .withArgs(actualAmount, toBN(0), expectedNextDeadline)
    })
    it('cannot be called more than once per minDripInterval', async function () {
      supplyBeforeDrip = await grt.totalSupply()
      const startAccrued = await l1Reservoir.getAccumulatedRewards(await latestBlock())
      expect(startAccrued).to.eq(0)
      const dripBlock = (await latestBlock()).add(1) // We're gonna drip in the next transaction
      const tracker = await RewardsTracker.create(
        supplyBeforeDrip,
        defaults.rewards.issuanceRate,
        dripBlock,
      )
      expect(await tracker.accRewards(dripBlock)).to.eq(0)
      const expectedNextDeadline = dripBlock.add(defaults.rewards.dripInterval)
      const expectedMintedAmount = await tracker.accRewards(expectedNextDeadline)

      const tx1 = await l1Reservoir
        .connect(keeper.signer)
        ['drip(uint256,uint256,uint256,address)'](toBN(0), toBN(0), toBN(0), keeper.address)

      const minInterval = toBN('200')
      await l1Reservoir.connect(governor.signer).setMinDripInterval(minInterval)

      const actualAmount = await grt.balanceOf(l1Reservoir.address)

      expect(toRound(actualAmount)).to.eq(toRound(expectedMintedAmount))
      await expect(tx1)
        .emit(l1Reservoir, 'RewardsDripped')
        .withArgs(actualAmount, toBN(0), expectedNextDeadline)
      await expect(tx1)
        .emit(grt, 'Transfer')
        .withArgs(AddressZero, l1Reservoir.address, actualAmount)

      const tx2 = l1Reservoir
        .connect(keeper.signer)
        ['drip(uint256,uint256,uint256,address)'](toBN(0), toBN(0), toBN(0), keeper.address)
      await expect(tx2).revertedWith('WAIT_FOR_MIN_INTERVAL')

      // We've had 1 block since the last drip so far, so we jump to one block before the interval is done
      await advanceBlocks(minInterval.sub(2))
      const tx3 = l1Reservoir
        .connect(keeper.signer)
        ['drip(uint256,uint256,uint256,address)'](toBN(0), toBN(0), toBN(0), keeper.address)
      await expect(tx3).revertedWith('WAIT_FOR_MIN_INTERVAL')

      await advanceBlocks(1)
      // Now we're over the interval so we can drip again
      const tx4 = l1Reservoir
        .connect(keeper.signer)
        ['drip(uint256,uint256,uint256,address)'](toBN(0), toBN(0), toBN(0), keeper.address)
      await expect(tx4).emit(l1Reservoir, 'RewardsDripped')
    })
    it('prevents locking eth in the contract if l2RewardsFraction is 0', async function () {
      const tx = l1Reservoir
        .connect(keeper.signer)
        ['drip(uint256,uint256,uint256,address)'](
          maxGas,
          gasPriceBid,
          maxSubmissionCost,
          keeper.address,
          { value: defaultEthValue },
        )
      await expect(tx).revertedWith('No eth value needed')
    })
    it('mints only a few more tokens if called on the next block', async function () {
      await sequentialDoubleDrip(toBN(0))
    })
    it('mints the right amount of tokens if called before the drip period is over', async function () {
      const dripInterval = toBN('100')
      await l1Reservoir.connect(governor.signer).setDripInterval(dripInterval)
      await sequentialDoubleDrip(toBN('50'), dripInterval)
    })
    it('mints the right amount of tokens filling the gap if called after the drip period is over', async function () {
      const dripInterval = toBN('100')
      await l1Reservoir.connect(governor.signer).setDripInterval(dripInterval)
      await sequentialDoubleDrip(toBN('150'), dripInterval)
    })
    it('sends the specified fraction of the rewards with a callhook to L2', async function () {
      await l1Reservoir.connect(governor.signer).setL2RewardsFraction(toGRT('0.5'))
      supplyBeforeDrip = await grt.totalSupply()
      const startAccrued = await l1Reservoir.getAccumulatedRewards(await latestBlock())
      expect(startAccrued).to.eq(0)
      const dripBlock = (await latestBlock()).add(1) // We're gonna drip in the next transaction
      const tracker = await RewardsTracker.create(
        supplyBeforeDrip,
        defaults.rewards.issuanceRate,
        dripBlock,
      )
      expect(await tracker.accRewards(dripBlock)).to.eq(0)
      const expectedNextDeadline = dripBlock.add(defaults.rewards.dripInterval)
      const expectedMintedAmount = await tracker.accRewards(expectedNextDeadline)
      const expectedSentToL2 = expectedMintedAmount.div(2)
      const tx = await l1Reservoir
        .connect(keeper.signer)
        ['drip(uint256,uint256,uint256,address)'](
          maxGas,
          gasPriceBid,
          maxSubmissionCost,
          keeper.address,
          { value: defaultEthValue },
        )
      const actualAmount = await grt.balanceOf(l1Reservoir.address)
      const escrowedAmount = await grt.balanceOf(bridgeEscrow.address)
      expect(toRound(actualAmount)).to.eq(toRound(expectedMintedAmount.sub(expectedSentToL2)))
      expect(toRound((await grt.totalSupply()).sub(supplyBeforeDrip))).to.eq(
        toRound(expectedMintedAmount),
      )
      expect(toRound(escrowedAmount)).to.eq(toRound(expectedSentToL2))
      await expect(tx)
        .emit(l1Reservoir, 'RewardsDripped')
        .withArgs(actualAmount.add(escrowedAmount), escrowedAmount, expectedNextDeadline)

      const l2IssuanceBase = (await l1Reservoir.issuanceBase())
        .mul(await l1Reservoir.l2RewardsFraction())
        .div(toGRT('1'))
      const issuanceRate = await l1Reservoir.issuanceRate()
      const expectedCallhookData = defaultAbiCoder.encode(
        ['uint256', 'uint256', 'uint256', 'uint256', 'address'],
        [l2IssuanceBase, issuanceRate, toBN('0'), toBN('0'), keeper.address],
      )
      const expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
        grt.address,
        l1Reservoir.address,
        mockL2Reservoir.address,
        escrowedAmount,
        expectedCallhookData,
      )
      await expect(tx)
        .emit(l1GraphTokenGateway, 'TxToL2')
        .withArgs(l1Reservoir.address, mockL2Gateway.address, toBN(1), expectedL2Data)
    })
    it('sends the specified fraction of the rewards with a keeper reward to L2', async function () {
      await l1Reservoir.connect(governor.signer).setL2RewardsFraction(toGRT('0.5'))
      await l1Reservoir.connect(governor.signer).setDripRewardPerBlock(toGRT('3'))
      await l1Reservoir.connect(governor.signer).setMinDripInterval(toBN('2'))

      await advanceBlocks(toBN('4'))

      supplyBeforeDrip = await grt.totalSupply()
      const issuanceBase = await l1Reservoir.issuanceBase()
      const startAccrued = await l1Reservoir.getAccumulatedRewards(await latestBlock())
      expect(startAccrued).to.eq(0)
      const dripBlock = (await latestBlock()).add(1) // We're gonna drip in the next transaction
      const expectedKeeperReward = dripBlock
        .sub(await l1Reservoir.lastRewardsUpdateBlock())
        .mul(toGRT('3'))
      const tracker = await RewardsTracker.create(
        issuanceBase,
        defaults.rewards.issuanceRate,
        dripBlock,
      )
      expect(await tracker.accRewards(dripBlock)).to.eq(0)
      const expectedNextDeadline = dripBlock.add(defaults.rewards.dripInterval)
      const expectedMintedRewards = await tracker.accRewards(expectedNextDeadline)
      const expectedMintedAmount = expectedMintedRewards.add(expectedKeeperReward)
      const expectedSentToL2 = expectedMintedRewards.div(2).add(expectedKeeperReward)
      const tx = await l1Reservoir
        .connect(keeper.signer)
        ['drip(uint256,uint256,uint256,address)'](
          maxGas,
          gasPriceBid,
          maxSubmissionCost,
          keeper.address,
          { value: defaultEthValue },
        )
      const actualAmount = await grt.balanceOf(l1Reservoir.address)
      const escrowedAmount = await grt.balanceOf(bridgeEscrow.address)

      expect(toRound(actualAmount)).to.eq(toRound(expectedMintedAmount.sub(expectedSentToL2)))
      expect(toRound((await grt.totalSupply()).sub(supplyBeforeDrip))).to.eq(
        toRound(expectedMintedAmount),
      )
      expect(toRound(escrowedAmount)).to.eq(toRound(expectedSentToL2))
      await expect(tx)
        .emit(l1Reservoir, 'RewardsDripped')
        .withArgs(actualAmount.add(escrowedAmount), escrowedAmount, expectedNextDeadline)

      const l2IssuanceBase = (await l1Reservoir.issuanceBase())
        .mul(await l1Reservoir.l2RewardsFraction())
        .div(toGRT('1'))
      const issuanceRate = await l1Reservoir.issuanceRate()
      const expectedCallhookData = defaultAbiCoder.encode(
        ['uint256', 'uint256', 'uint256', 'uint256', 'address'],
        [l2IssuanceBase, issuanceRate, toBN('0'), expectedKeeperReward, keeper.address],
      )
      const expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
        grt.address,
        l1Reservoir.address,
        mockL2Reservoir.address,
        escrowedAmount,
        expectedCallhookData,
      )
      await expect(tx)
        .emit(l1GraphTokenGateway, 'TxToL2')
        .withArgs(l1Reservoir.address, mockL2Gateway.address, toBN(1), expectedL2Data)
    })
    it('sends the outstanding amount if the L2 rewards fraction changes', async function () {
      await l1Reservoir.connect(governor.signer).setL2RewardsFraction(toGRT('0.5'))
      supplyBeforeDrip = await grt.totalSupply()
      const startAccrued = await l1Reservoir.getAccumulatedRewards(await latestBlock())
      expect(startAccrued).to.eq(0)
      const dripBlock = (await latestBlock()).add(1) // We're gonna drip in the next transaction
      const tracker = await RewardsTracker.create(
        supplyBeforeDrip,
        defaults.rewards.issuanceRate,
        dripBlock,
      )
      expect(await tracker.accRewards(dripBlock)).to.eq(0)
      const expectedNextDeadline = dripBlock.add(defaults.rewards.dripInterval)
      const expectedMintedAmount = await tracker.accRewards(expectedNextDeadline)
      const expectedSentToL2 = expectedMintedAmount.div(2)
      const tx = await l1Reservoir
        .connect(keeper.signer)
        ['drip(uint256,uint256,uint256,address)'](
          maxGas,
          gasPriceBid,
          maxSubmissionCost,
          keeper.address,
          { value: defaultEthValue },
        )
      const actualAmount = await grt.balanceOf(l1Reservoir.address)
      const escrowedAmount = await grt.balanceOf(bridgeEscrow.address)
      expect(toRound(actualAmount)).to.eq(toRound(expectedMintedAmount.sub(expectedSentToL2)))
      expect(toRound((await grt.totalSupply()).sub(supplyBeforeDrip))).to.eq(
        toRound(expectedMintedAmount),
      )
      expect(toRound(escrowedAmount)).to.eq(toRound(expectedSentToL2))
      await expect(tx)
        .emit(l1Reservoir, 'RewardsDripped')
        .withArgs(actualAmount.add(escrowedAmount), escrowedAmount, expectedNextDeadline)

      let l2IssuanceBase = (await l1Reservoir.issuanceBase())
        .mul(await l1Reservoir.l2RewardsFraction())
        .div(toGRT('1'))
      const issuanceRate = await l1Reservoir.issuanceRate()
      let expectedCallhookData = defaultAbiCoder.encode(
        ['uint256', 'uint256', 'uint256', 'uint256', 'address'],
        [l2IssuanceBase, issuanceRate, toBN('0'), toBN('0'), keeper.address],
      )
      let expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
        grt.address,
        l1Reservoir.address,
        mockL2Reservoir.address,
        escrowedAmount,
        expectedCallhookData,
      )
      await expect(tx)
        .emit(l1GraphTokenGateway, 'TxToL2')
        .withArgs(l1Reservoir.address, mockL2Gateway.address, toBN(1), expectedL2Data)

      await tracker.snapshotRewards()

      await l1Reservoir.connect(governor.signer).setL2RewardsFraction(toGRT('0.8'))
      supplyBeforeDrip = await grt.totalSupply()
      const secondDripBlock = (await latestBlock()).add(1)
      const expectedNewNextDeadline = secondDripBlock.add(defaults.rewards.dripInterval)
      const rewardsUntilSecondDripBlock = await tracker.accRewards(secondDripBlock)
      const expectedTotalRewards = await tracker.accRewards(expectedNewNextDeadline)
      const expectedNewMintedAmount = expectedTotalRewards.sub(expectedMintedAmount)
      // The amount sent to L2 should cover up to the new drip block with the old fraction,
      // and from then onwards with the new fraction
      const expectedNewTotalSentToL2 = rewardsUntilSecondDripBlock
        .div(2)
        .add(expectedTotalRewards.sub(rewardsUntilSecondDripBlock).mul(8).div(10))

      const tx2 = await l1Reservoir
        .connect(keeper.signer)
        ['drip(uint256,uint256,uint256,address)'](
          maxGas,
          gasPriceBid,
          maxSubmissionCost,
          keeper.address,
          { value: defaultEthValue },
        )
      const newActualAmount = await grt.balanceOf(l1Reservoir.address)
      const newEscrowedAmount = await grt.balanceOf(bridgeEscrow.address)
      expect(toRound(newActualAmount)).to.eq(
        toRound(expectedTotalRewards.sub(expectedNewTotalSentToL2)),
      )
      expect(toRound((await grt.totalSupply()).sub(supplyBeforeDrip))).to.eq(
        toRound(expectedNewMintedAmount),
      )
      expect(toRound(newEscrowedAmount)).to.eq(toRound(expectedNewTotalSentToL2))
      l2IssuanceBase = (await l1Reservoir.issuanceBase())
        .mul(await l1Reservoir.l2RewardsFraction())
        .div(toGRT('1'))
      expectedCallhookData = defaultAbiCoder.encode(
        ['uint256', 'uint256', 'uint256', 'uint256', 'address'],
        [
          l2IssuanceBase,
          issuanceRate,
          toBN('1'), // Incremented nonce
          toBN('0'),
          keeper.address,
        ],
      )
      expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
        grt.address,
        l1Reservoir.address,
        mockL2Reservoir.address,
        newEscrowedAmount.sub(escrowedAmount),
        expectedCallhookData,
      )
      await expect(tx2)
        .emit(l1GraphTokenGateway, 'TxToL2')
        .withArgs(l1Reservoir.address, mockL2Gateway.address, toBN(2), expectedL2Data)
      await expect(tx2)
        .emit(l1Reservoir, 'RewardsDripped')
        .withArgs(
          newActualAmount.add(newEscrowedAmount).sub(actualAmount.add(escrowedAmount)),
          newEscrowedAmount.sub(escrowedAmount),
          expectedNewNextDeadline,
        )
    })
    it('sends the outstanding amount if the L2 rewards fraction stays constant', async function () {
      await l1Reservoir.connect(governor.signer).setL2RewardsFraction(toGRT('0.5'))
      supplyBeforeDrip = await grt.totalSupply()
      const startAccrued = await l1Reservoir.getAccumulatedRewards(await latestBlock())
      expect(startAccrued).to.eq(0)
      const dripBlock = (await latestBlock()).add(1) // We're gonna drip in the next transaction
      const tracker = await RewardsTracker.create(
        supplyBeforeDrip,
        defaults.rewards.issuanceRate,
        dripBlock,
      )
      expect(await tracker.accRewards(dripBlock)).to.eq(0)
      const expectedNextDeadline = dripBlock.add(defaults.rewards.dripInterval)
      const expectedMintedAmount = await tracker.accRewards(expectedNextDeadline)
      const expectedSentToL2 = expectedMintedAmount.div(2)
      const tx = await l1Reservoir
        .connect(keeper.signer)
        ['drip(uint256,uint256,uint256,address)'](
          maxGas,
          gasPriceBid,
          maxSubmissionCost,
          keeper.address,
          { value: defaultEthValue },
        )
      const actualAmount = await grt.balanceOf(l1Reservoir.address)
      const escrowedAmount = await grt.balanceOf(bridgeEscrow.address)
      expect(toRound(actualAmount)).to.eq(toRound(expectedMintedAmount.sub(expectedSentToL2)))
      expect(toRound((await grt.totalSupply()).sub(supplyBeforeDrip))).to.eq(
        toRound(expectedMintedAmount),
      )
      expect(toRound(escrowedAmount)).to.eq(toRound(expectedSentToL2))
      await expect(tx)
        .emit(l1Reservoir, 'RewardsDripped')
        .withArgs(actualAmount.add(escrowedAmount), escrowedAmount, expectedNextDeadline)

      let l2IssuanceBase = (await l1Reservoir.issuanceBase())
        .mul(await l1Reservoir.l2RewardsFraction())
        .div(toGRT('1'))
      const issuanceRate = await l1Reservoir.issuanceRate()
      let expectedCallhookData = defaultAbiCoder.encode(
        ['uint256', 'uint256', 'uint256', 'uint256', 'address'],
        [l2IssuanceBase, issuanceRate, toBN('0'), toBN('0'), keeper.address],
      )
      let expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
        grt.address,
        l1Reservoir.address,
        mockL2Reservoir.address,
        escrowedAmount,
        expectedCallhookData,
      )
      await expect(tx)
        .emit(l1GraphTokenGateway, 'TxToL2')
        .withArgs(l1Reservoir.address, mockL2Gateway.address, toBN(1), expectedL2Data)

      await tracker.snapshotRewards()

      supplyBeforeDrip = await grt.totalSupply()
      const secondDripBlock = (await latestBlock()).add(1)
      const expectedNewNextDeadline = secondDripBlock.add(defaults.rewards.dripInterval)
      const expectedTotalRewards = await tracker.accRewards(expectedNewNextDeadline)
      const expectedNewMintedAmount = expectedTotalRewards.sub(expectedMintedAmount)
      // The amount sent to L2 should cover up to the new drip block with the old fraction,
      // and from then onwards with the new fraction
      const expectedNewTotalSentToL2 = expectedTotalRewards.div(2)

      const tx2 = await l1Reservoir
        .connect(keeper.signer)
        ['drip(uint256,uint256,uint256,address)'](
          maxGas,
          gasPriceBid,
          maxSubmissionCost,
          keeper.address,
          { value: defaultEthValue },
        )
      const newActualAmount = await grt.balanceOf(l1Reservoir.address)
      const newEscrowedAmount = await grt.balanceOf(bridgeEscrow.address)
      expect(toRound(newActualAmount)).to.eq(
        toRound(expectedTotalRewards.sub(expectedNewTotalSentToL2)),
      )
      expect(toRound((await grt.totalSupply()).sub(supplyBeforeDrip))).to.eq(
        toRound(expectedNewMintedAmount),
      )
      expect(toRound(newEscrowedAmount)).to.eq(toRound(expectedNewTotalSentToL2))
      l2IssuanceBase = (await l1Reservoir.issuanceBase())
        .mul(await l1Reservoir.l2RewardsFraction())
        .div(toGRT('1'))
      expectedCallhookData = defaultAbiCoder.encode(
        ['uint256', 'uint256', 'uint256', 'uint256', 'address'],
        [
          l2IssuanceBase,
          issuanceRate,
          toBN('1'), // Incremented nonce
          toBN('0'),
          keeper.address,
        ],
      )
      expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
        grt.address,
        l1Reservoir.address,
        mockL2Reservoir.address,
        newEscrowedAmount.sub(escrowedAmount),
        expectedCallhookData,
      )
      await expect(tx2)
        .emit(l1GraphTokenGateway, 'TxToL2')
        .withArgs(l1Reservoir.address, mockL2Gateway.address, toBN(2), expectedL2Data)
      await expect(tx2)
        .emit(l1Reservoir, 'RewardsDripped')
        .withArgs(
          newActualAmount.add(newEscrowedAmount).sub(actualAmount.add(escrowedAmount)),
          newEscrowedAmount.sub(escrowedAmount),
          expectedNewNextDeadline,
        )
    })

    it('reverts for a while but can be called again later if L2 fraction goes to zero', async function () {
      await l1Reservoir.connect(governor.signer).setL2RewardsFraction(toGRT('0.5'))

      // First drip call, sending half the rewards to L2
      supplyBeforeDrip = await grt.totalSupply()
      const startAccrued = await l1Reservoir.getAccumulatedRewards(await latestBlock())
      expect(startAccrued).to.eq(0)
      const dripBlock = (await latestBlock()).add(1) // We're gonna drip in the next transaction
      const tracker = await RewardsTracker.create(
        supplyBeforeDrip,
        defaults.rewards.issuanceRate,
        dripBlock,
      )
      expect(await tracker.accRewards(dripBlock)).to.eq(0)
      const expectedNextDeadline = dripBlock.add(defaults.rewards.dripInterval)
      const expectedMintedAmount = await tracker.accRewards(expectedNextDeadline)
      const expectedSentToL2 = expectedMintedAmount.div(2)
      const tx = await l1Reservoir
        .connect(keeper.signer)
        ['drip(uint256,uint256,uint256,address)'](
          maxGas,
          gasPriceBid,
          maxSubmissionCost,
          keeper.address,
          { value: defaultEthValue },
        )
      const actualAmount = await grt.balanceOf(l1Reservoir.address)
      const escrowedAmount = await grt.balanceOf(bridgeEscrow.address)
      expect(toRound(actualAmount)).to.eq(toRound(expectedMintedAmount.sub(expectedSentToL2)))
      expect(toRound((await grt.totalSupply()).sub(supplyBeforeDrip))).to.eq(
        toRound(expectedMintedAmount),
      )
      expect(toRound(escrowedAmount)).to.eq(toRound(expectedSentToL2))
      await expect(tx)
        .emit(l1Reservoir, 'RewardsDripped')
        .withArgs(actualAmount.add(escrowedAmount), escrowedAmount, expectedNextDeadline)

      let l2IssuanceBase = (await l1Reservoir.issuanceBase())
        .mul(await l1Reservoir.l2RewardsFraction())
        .div(toGRT('1'))
      const issuanceRate = await l1Reservoir.issuanceRate()
      let expectedCallhookData = defaultAbiCoder.encode(
        ['uint256', 'uint256', 'uint256', 'uint256', 'address'],
        [l2IssuanceBase, issuanceRate, toBN('0'), toBN('0'), keeper.address],
      )
      let expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
        grt.address,
        l1Reservoir.address,
        mockL2Reservoir.address,
        escrowedAmount,
        expectedCallhookData,
      )
      await expect(tx)
        .emit(l1GraphTokenGateway, 'TxToL2')
        .withArgs(l1Reservoir.address, mockL2Gateway.address, toBN(1), expectedL2Data)

      await tracker.snapshotRewards()

      await l1Reservoir.connect(governor.signer).setL2RewardsFraction(toGRT('0'))

      // Second attempt to drip immediately afterwards will revert, because we
      // would have to send negative tokens to L2 to compensate
      const tx2 = l1Reservoir
        .connect(keeper.signer)
        ['drip(uint256,uint256,uint256,address)'](
          maxGas,
          gasPriceBid,
          maxSubmissionCost,
          keeper.address,
          { value: defaultEthValue },
        )
      await expect(tx2).revertedWith(
        'Negative amount would be sent to L2, wait before calling again',
      )

      await advanceBlocks(await l1Reservoir.dripInterval())

      // Now we should be able to drip again, and a small amount will be sent to L2
      // to cover the few blocks since the drip interval was over
      supplyBeforeDrip = await grt.totalSupply()
      const secondDripBlock = (await latestBlock()).add(1)
      const expectedNewNextDeadline = secondDripBlock.add(defaults.rewards.dripInterval)
      const rewardsUntilSecondDripBlock = await tracker.accRewards(secondDripBlock)
      const expectedTotalRewards = await tracker.accRewards(expectedNewNextDeadline)
      const expectedNewMintedAmount = expectedTotalRewards.sub(expectedMintedAmount)
      // The amount sent to L2 should cover up to the new drip block with the old fraction,
      // and from then onwards with the new fraction, that is zero
      const expectedNewTotalSentToL2 = rewardsUntilSecondDripBlock.div(2)

      const tx3 = await l1Reservoir
        .connect(keeper.signer)
        ['drip(uint256,uint256,uint256,address)'](
          maxGas,
          gasPriceBid,
          maxSubmissionCost,
          keeper.address,
          { value: defaultEthValue },
        )
      const newActualAmount = await grt.balanceOf(l1Reservoir.address)
      const newEscrowedAmount = await grt.balanceOf(bridgeEscrow.address)
      expect(toRound(newActualAmount)).to.eq(
        toRound(expectedTotalRewards.sub(expectedNewTotalSentToL2)),
      )
      expect(toRound((await grt.totalSupply()).sub(supplyBeforeDrip))).to.eq(
        toRound(expectedNewMintedAmount),
      )
      expect(toRound(newEscrowedAmount)).to.eq(toRound(expectedNewTotalSentToL2))
      l2IssuanceBase = (await l1Reservoir.issuanceBase())
        .mul(await l1Reservoir.l2RewardsFraction())
        .div(toGRT('1'))
      expectedCallhookData = defaultAbiCoder.encode(
        ['uint256', 'uint256', 'uint256', 'uint256', 'address'],
        [
          l2IssuanceBase,
          issuanceRate,
          toBN('1'), // Incremented nonce
          toBN('0'),
          keeper.address,
        ],
      )
      expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
        grt.address,
        l1Reservoir.address,
        mockL2Reservoir.address,
        newEscrowedAmount.sub(escrowedAmount),
        expectedCallhookData,
      )
      await expect(tx3)
        .emit(l1GraphTokenGateway, 'TxToL2')
        .withArgs(l1Reservoir.address, mockL2Gateway.address, toBN(2), expectedL2Data)
      await expect(tx3)
        .emit(l1Reservoir, 'RewardsDripped')
        .withArgs(
          newActualAmount.add(newEscrowedAmount).sub(actualAmount.add(escrowedAmount)),
          newEscrowedAmount.sub(escrowedAmount),
          expectedNewNextDeadline,
        )
    })
  })

  context('calculating rewards', async function () {
    beforeEach(async function () {
      // 5% minute rate (4 blocks)
      await l1Reservoir.connect(governor.signer).setIssuanceRate(ISSUANCE_RATE_PER_BLOCK)
      supplyBeforeDrip = await grt.totalSupply()
      await l1Reservoir
        .connect(keeper.signer)
        ['drip(uint256,uint256,uint256,address)'](toBN(0), toBN(0), toBN(0), keeper.address)
      dripBlock = await latestBlock()
    })

    describe('getAccumulatedRewards', function () {
      it('returns rewards accrued after some blocks', async function () {
        await shouldGetNewRewards(supplyBeforeDrip)
      })
      it('returns zero if evaluated at the block where reservoir had the first drip', async function () {
        await shouldGetNewRewards(
          supplyBeforeDrip,
          ISSUANCE_RATE_PERIODS,
          dripBlock,
          toBN(0),
          false,
        )
      })
      it('returns the supply times issuance rate one block after the first drip', async function () {
        const expectedVal = supplyBeforeDrip
          .mul(ISSUANCE_RATE_PER_BLOCK.sub(toGRT(1)))
          .div(toGRT(1))
        await shouldGetNewRewards(
          supplyBeforeDrip,
          ISSUANCE_RATE_PERIODS,
          dripBlock.add(1),
          expectedVal,
          false,
        )
      })
      it('returns the rewards for a block some time in the future', async function () {
        await shouldGetNewRewards(supplyBeforeDrip, toBN(1), dripBlock.add(10000))
      })
    })
    describe('getNewRewards', function () {
      const computeDelta = function (t1: BigNumber, t0: BigNumber, lambda = toBN(0)): BigNumber {
        const deltaT = new BN(t1.toString()).minus(new BN(t0.toString()))
        const rate = new BN(ISSUANCE_RATE_PER_BLOCK.toString()).div(1e18)
        const supply = new BN(supplyBeforeDrip.toString())
        return toBN(supply.times(rate.pow(deltaT)).minus(supply).precision(18).toString(10))
          .mul(toGRT('1').sub(lambda))
          .div(toGRT('1'))
      }
      it('computes the rewards delta between the last drip block and the current block', async function () {
        const t0 = dripBlock
        const t1 = t0.add(200)
        const expectedVal = computeDelta(t1, t0)
        expect(toRound(await l1Reservoir.getNewRewards(t1))).to.eq(toRound(expectedVal))
      })
      it('returns zero rewards if the time delta is zero', async function () {
        const t0 = dripBlock
        const expectedVal = toBN('0')
        expect(await l1Reservoir.getNewRewards(t0)).to.eq(expectedVal)
      })
      it('computes the rewards delta between a past drip block and a future block', async function () {
        await advanceBlocks(20)
        const t0 = dripBlock
        const t1 = t0.add(100)
        const expectedVal = computeDelta(t1, t0)
        expect(toRound(await l1Reservoir.getNewRewards(t1))).to.eq(toRound(expectedVal))
      })
      it('computes the rewards delta between a past drip block and the current block', async function () {
        await advanceBlocks(20)
        const t0 = dripBlock
        const t1 = await latestBlock()
        const expectedVal = computeDelta(t1, t0)
        expect(toRound(await l1Reservoir.getNewRewards(t1))).to.eq(toRound(expectedVal))
      })
      it('computes the rewards delta considering the L2 rewards fraction', async function () {
        const lambda = toGRT('0.32')
        await l1Reservoir.connect(governor.signer).setL2RewardsFraction(lambda)
        await l1Reservoir
          .connect(keeper.signer)
          ['drip(uint256,uint256,uint256,address)'](
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            keeper.address,
            { value: defaultEthValue },
          )
        supplyBeforeDrip = await l1Reservoir.issuanceBase() // Has been updated accordingly
        dripBlock = await latestBlock()
        await advanceBlocks(20)
        const t0 = dripBlock
        const t1 = await latestBlock()

        const expectedVal = computeDelta(t1, t0, lambda)
        expect(toRound(await l1Reservoir.getNewRewards(t1))).to.eq(toRound(expectedVal))
      })
    })
  })

  describe('pow', function () {
    it('exponentiation works under normal boundaries (annual rate from 1% to 700%, 90 days period)', async function () {
      const baseRatio = toGRT('0.000000004641377923') // 1% annual rate
      const timePeriods = (60 * 60 * 24 * 10) / 15 // 90 days in blocks
      const powPrecision = 14 // Compare up to this amount of significant digits
      BN.config({ POW_PRECISION: 100 })
      for (let i = 0; i < 50; i = i + 4) {
        const r = baseRatio.mul(i * 4).add(toGRT('1'))
        const h = await reservoirMock.pow(r, timePeriods, toGRT('1'))
        console.log('\tr:', formatGRT(r), '=> c:', formatGRT(h))
        expect(new BN(h.toString()).precision(powPrecision).toString(10)).to.eq(
          new BN(r.toString())
            .div(1e18)
            .pow(timePeriods)
            .times(1e18)
            .precision(powPrecision)
            .toString(10),
        )
      }
    })
  })
})
