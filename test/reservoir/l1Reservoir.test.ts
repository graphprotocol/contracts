import { expect } from 'chai'
import { BigNumber, constants, utils } from 'ethers'

import { defaults, deployContract } from '../lib/deployment'
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
  provider,
} from '../lib/testHelpers'
import { L1Reservoir } from '../../build/types/L1Reservoir'
import { BridgeEscrow } from '../../build/types/BridgeEscrow'

import path from 'path'
import { Artifacts } from 'hardhat/internal/artifacts'
import { Interface } from 'ethers/lib/utils'
import { L1GraphTokenGateway } from '../../build/types/L1GraphTokenGateway'
const ARTIFACTS_PATH = path.resolve('build/contracts')
const artifacts = new Artifacts(ARTIFACTS_PATH)
const l2ReservoirAbi = artifacts.readArtifactSync('L2Reservoir').abi
const l2ReservoirIface = new Interface(l2ReservoirAbi)

const { AddressZero } = constants
const toRound = (n: BigNumber) => formatGRT(n).split('.')[0]

const maxGas = toBN('1000000')
const maxSubmissionCost = toBN('7')
const gasPriceBid = toBN('2')
const defaultEthValue = maxSubmissionCost.add(maxGas.mul(gasPriceBid))

describe('L1Reservoir', () => {
  let governor: Account
  let testAccount1: Account
  let mockRouter: Account
  let mockL2GRT: Account
  let mockL2Gateway: Account
  let mockL2Reservoir: Account
  let fixture: NetworkFixture

  let grt: GraphToken
  let reservoirMock: ReservoirMock
  let l1Reservoir: L1Reservoir
  let bridgeEscrow: BridgeEscrow
  let l1GraphTokenGateway: L1GraphTokenGateway

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
    // Initial snapshot defines the first lastRewardsUpdateBlock
    await l1Reservoir.connect(governor.signer).initialSnapshot(toBN(0))
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
    const tx1 = await l1Reservoir.connect(governor.signer).drip(toBN(0), toBN(0), toBN(0))
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

    const tx2 = await l1Reservoir.connect(governor.signer).drip(toBN(0), toBN(0), toBN(0))
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
    ;[governor, testAccount1, mockRouter, mockL2GRT, mockL2Gateway, mockL2Reservoir] =
      await getAccounts()

    fixture = new NetworkFixture()
    fixtureContracts = await fixture.load(governor.signer)
    ;({ grt, l1Reservoir, bridgeEscrow, l1GraphTokenGateway } = fixtureContracts)

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
      it('rejects call if unauthorized', async function () {
        const tx = l1Reservoir.connect(testAccount1.signer).initialSnapshot(toGRT('1.025'))
        await expect(tx).revertedWith('Caller must be Controller governor')
      })

      it('snapshots the total GRT supply', async function () {
        const tx = l1Reservoir.connect(governor.signer).initialSnapshot(toGRT('0'))
        const supply = await grt.totalSupply()
        await expect(tx)
          .emit(l1Reservoir, 'InitialSnapshotTaken')
          .withArgs(await latestBlock(), supply, toGRT('0'))
        expect(await grt.balanceOf(l1Reservoir.address)).to.eq(toGRT('0'))
        expect(await l1Reservoir.issuanceBase()).to.eq(supply)
        expect(await l1Reservoir.lastRewardsUpdateBlock()).to.eq(await latestBlock())
      })
      it('mints pending rewards and includes them in the snapshot', async function () {
        const pending = toGRT('10000000')
        const tx = l1Reservoir.connect(governor.signer).initialSnapshot(pending)
        const supply = await grt.totalSupply()
        const expectedSupply = supply.add(pending)
        await expect(tx)
          .emit(l1Reservoir, 'InitialSnapshotTaken')
          .withArgs(await latestBlock(), expectedSupply, pending)
        expect(await grt.balanceOf(l1Reservoir.address)).to.eq(pending)
        expect(await l1Reservoir.issuanceBase()).to.eq(expectedSupply)
        expect(await l1Reservoir.lastRewardsUpdateBlock()).to.eq(await latestBlock())
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
        tx = l1Reservoir.connect(governor.signer).drip(toBN(0), toBN(0), toBN(0))
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
          .connect(governor.signer)
          .drip(maxGas, gasPriceBid, maxSubmissionCost, { value: defaultEthValue })
        await expect(tx).emit(l1Reservoir, 'L2RewardsFractionUpdated').withArgs(newValue)
        expect(await l1Reservoir.l2RewardsFraction()).eq(newValue)
      })
    })
  })

  // TODO test that rewardsManager.updateAccRewardsPerSignal is called when
  // issuanceRate or l2RewardsFraction is updated
  describe('drip', function () {
    it('mints rewards for the next week', async function () {
      // Initial snapshot defines the first lastRewardsUpdateBlock
      await l1Reservoir.connect(governor.signer).initialSnapshot(toBN(0))
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
      const tx = await l1Reservoir.connect(governor.signer).drip(toBN(0), toBN(0), toBN(0))
      const actualAmount = await grt.balanceOf(l1Reservoir.address)
      expect(toRound(actualAmount)).to.eq(toRound(expectedMintedAmount))
      expect(await l1Reservoir.issuanceBase()).to.eq(supplyBeforeDrip)
      await expect(tx)
        .emit(l1Reservoir, 'RewardsDripped')
        .withArgs(actualAmount, toBN(0), expectedNextDeadline)
    })
    it('has no effect if called a second time in the same block', async function () {
      // Initial snapshot defines the first lastRewardsUpdateBlock
      await l1Reservoir.connect(governor.signer).initialSnapshot(toBN(0))
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
      await provider().send('evm_setAutomine', [false])
      const tx1 = await l1Reservoir.connect(governor.signer).drip(toBN(0), toBN(0), toBN(0))
      const tx2 = await l1Reservoir.connect(governor.signer).drip(toBN(0), toBN(0), toBN(0))
      await provider().send('evm_mine', [])
      await provider().send('evm_setAutomine', [true])

      const actualAmount = await grt.balanceOf(l1Reservoir.address)
      expect(await latestBlock()).eq(dripBlock) // Just in case disabling automine stops working
      expect(toRound(actualAmount)).to.eq(toRound(expectedMintedAmount))
      await expect(tx1)
        .emit(l1Reservoir, 'RewardsDripped')
        .withArgs(actualAmount, toBN(0), expectedNextDeadline)
      await expect(tx1)
        .emit(grt, 'Transfer')
        .withArgs(AddressZero, l1Reservoir.address, actualAmount)
      await expect(tx2)
        .emit(l1Reservoir, 'RewardsDripped')
        .withArgs(toBN(0), toBN(0), expectedNextDeadline)
      await expect(tx2).not.emit(grt, 'Transfer')
    })
    it('prevents locking eth in the contract if l2RewardsFraction is 0', async function () {
      const tx = l1Reservoir
        .connect(governor.signer)
        .drip(maxGas, gasPriceBid, maxSubmissionCost, { value: defaultEthValue })
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
      await l1Reservoir.connect(governor.signer).initialSnapshot(toBN(0))
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
        .connect(governor.signer)
        .drip(maxGas, gasPriceBid, maxSubmissionCost, { value: defaultEthValue })
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
      const expectedCallhookData = l2ReservoirIface.encodeFunctionData('receiveDrip', [
        l2IssuanceBase,
        issuanceRate,
        toBN('0'),
      ])
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
      await l1Reservoir.connect(governor.signer).initialSnapshot(toBN(0))
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
        .connect(governor.signer)
        .drip(maxGas, gasPriceBid, maxSubmissionCost, { value: defaultEthValue })
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
      let expectedCallhookData = l2ReservoirIface.encodeFunctionData('receiveDrip', [
        l2IssuanceBase,
        issuanceRate,
        toBN('0'),
      ])
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
        .connect(governor.signer)
        .drip(maxGas, gasPriceBid, maxSubmissionCost, { value: defaultEthValue })
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
      expectedCallhookData = l2ReservoirIface.encodeFunctionData('receiveDrip', [
        l2IssuanceBase,
        issuanceRate,
        toBN('1'), // Incremented nonce
      ])
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
      await l1Reservoir.connect(governor.signer).initialSnapshot(toBN(0))
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
        .connect(governor.signer)
        .drip(maxGas, gasPriceBid, maxSubmissionCost, { value: defaultEthValue })
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
      let expectedCallhookData = l2ReservoirIface.encodeFunctionData('receiveDrip', [
        l2IssuanceBase,
        issuanceRate,
        toBN('0'),
      ])
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
      const rewardsUntilSecondDripBlock = await tracker.accRewards(secondDripBlock)
      const expectedTotalRewards = await tracker.accRewards(expectedNewNextDeadline)
      const expectedNewMintedAmount = expectedTotalRewards.sub(expectedMintedAmount)
      // The amount sent to L2 should cover up to the new drip block with the old fraction,
      // and from then onwards with the new fraction
      const expectedNewTotalSentToL2 = expectedTotalRewards.div(2)

      const tx2 = await l1Reservoir
        .connect(governor.signer)
        .drip(maxGas, gasPriceBid, maxSubmissionCost, { value: defaultEthValue })
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
      expectedCallhookData = l2ReservoirIface.encodeFunctionData('receiveDrip', [
        l2IssuanceBase,
        issuanceRate,
        toBN('1'), // Incremented nonce
      ])
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
  })

  context('calculating rewards', async function () {
    beforeEach(async function () {
      // 5% minute rate (4 blocks)
      await l1Reservoir.connect(governor.signer).setIssuanceRate(ISSUANCE_RATE_PER_BLOCK)
      supplyBeforeDrip = await grt.totalSupply()
      await l1Reservoir.drip(toBN(0), toBN(0), toBN(0))
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
        await l1Reservoir.drip(maxGas, gasPriceBid, maxSubmissionCost, { value: defaultEthValue })
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
