import { expect } from 'chai'
import { BigNumber, constants, ContractTransaction, utils } from 'ethers'

import { L2FixtureContracts, NetworkFixture } from '../lib/fixtures'

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
  getL2SignerFromL1,
} from '../lib/testHelpers'
import { L2Reservoir } from '../../build/types/L2Reservoir'

import { L2GraphTokenGateway } from '../../build/types/L2GraphTokenGateway'
import { L2GraphToken } from '../../build/types/L2GraphToken'

const toRound = (n: BigNumber) => formatGRT(n).split('.')[0]

const dripAmount = toBN('5851557519569225000000000')
const dripNormalizedSupply = toGRT('10004000000')
const dripIssuanceRate = toBN('1000000023206889619')

describe('L2Reservoir', () => {
  let governor: Account
  let testAccount1: Account
  let mockRouter: Account
  let mockL1GRT: Account
  let mockL1Gateway: Account
  let mockL1Reservoir: Account
  let fixture: NetworkFixture

  let grt: L2GraphToken
  let l2Reservoir: L2Reservoir
  let l2GraphTokenGateway: L2GraphTokenGateway

  let fixtureContracts: L2FixtureContracts

  let normalizedSupply: BigNumber
  let dripBlock: BigNumber

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
    const startAccrued = await l2Reservoir.getAccumulatedRewards(await latestBlock())
    // Jump
    await advanceBlocks(nBlocksToAdvance)

    // -- t1 --

    // Contract calculation
    if (!blockToQuery) {
      blockToQuery = await latestBlock()
    }
    const contractAccrued = await l2Reservoir.getAccumulatedRewards(blockToQuery)
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

  const gatewayFinalizeTransfer = async (callhookData: string): Promise<ContractTransaction> => {
    const mockL1GatewayL2Alias = await getL2SignerFromL1(mockL1Gateway.address)
    await testAccount1.signer.sendTransaction({
      to: await mockL1GatewayL2Alias.getAddress(),
      value: utils.parseUnits('1', 'ether'),
    })
    const data = utils.defaultAbiCoder.encode(['bytes', 'bytes'], ['0x', callhookData])
    const tx = l2GraphTokenGateway
      .connect(mockL1GatewayL2Alias)
      .finalizeInboundTransfer(
        mockL1GRT.address,
        mockL1Reservoir.address,
        l2Reservoir.address,
        dripAmount,
        data,
      )
    return tx
  }

  const validGatewayFinalizeTransfer = async (
    callhookData: string,
  ): Promise<ContractTransaction> => {
    const tx = await gatewayFinalizeTransfer(callhookData)
    await expect(tx)
      .emit(l2GraphTokenGateway, 'DepositFinalized')
      .withArgs(mockL1GRT.address, mockL1Reservoir.address, l2Reservoir.address, dripAmount)

    await expect(tx).emit(grt, 'BridgeMinted').withArgs(l2Reservoir.address, dripAmount)

    // newly minted GRT
    const receiverBalance = await grt.balanceOf(l2Reservoir.address)
    await expect(receiverBalance).eq(dripAmount)
    return tx
  }

  before(async function () {
    ;[governor, testAccount1, mockRouter, mockL1GRT, mockL1Gateway, mockL1Reservoir] =
      await getAccounts()

    fixture = new NetworkFixture()
    fixtureContracts = await fixture.loadL2(governor.signer)
    ;({ grt, l2Reservoir, l2GraphTokenGateway } = fixtureContracts)
    await fixture.configureL2Bridge(
      governor.signer,
      fixtureContracts,
      mockRouter.address,
      mockL1GRT.address,
      mockL1Gateway.address,
      mockL1Reservoir.address,
    )
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('setNextDripNonce', async function () {
    it('rejects unauthorized calls', async function () {
      const tx = l2Reservoir.connect(testAccount1.signer).setNextDripNonce(toBN('10'))
      await expect(tx).revertedWith('Caller must be Controller governor')
    })
    it('sets the next expected drip nonce', async function () {
      const tx = l2Reservoir.connect(governor.signer).setNextDripNonce(toBN('10'))
      await expect(tx).emit(l2Reservoir, 'NextDripNonceUpdated').withArgs(toBN('10'))
      await expect(await l2Reservoir.nextDripNonce()).to.eq(toBN('10'))
    })
  })
  describe('receiveDrip', async function () {
    it('rejects the call when not called by the gateway', async function () {
      const tx = l2Reservoir
        .connect(governor.signer)
        .receiveDrip(dripNormalizedSupply, dripIssuanceRate, toBN('0'))
      await expect(tx).revertedWith('ONLY_GATEWAY')
    })
    it('rejects the call when received out of order', async function () {
      normalizedSupply = dripNormalizedSupply
      let receiveDripTx = await l2Reservoir.populateTransaction.receiveDrip(
        dripNormalizedSupply,
        dripIssuanceRate,
        toBN('0'),
      )
      const tx = await validGatewayFinalizeTransfer(receiveDripTx.data)
      dripBlock = await latestBlock()
      await expect(await l2Reservoir.issuanceBase()).to.eq(dripNormalizedSupply)
      await expect(await l2Reservoir.issuanceRate()).to.eq(dripIssuanceRate)
      await expect(tx).emit(l2Reservoir, 'DripReceived').withArgs(dripNormalizedSupply)

      // Incorrect nonce
      receiveDripTx = await l2Reservoir.populateTransaction.receiveDrip(
        dripNormalizedSupply.add(1),
        dripIssuanceRate.add(1),
        toBN('2'),
      )
      const tx2 = gatewayFinalizeTransfer(receiveDripTx.data)
      dripBlock = await latestBlock()
      await expect(tx2).revertedWith('CALLHOOK_FAILED') // Gateway overrides revert message
    })
    it('updates the normalized supply cache', async function () {
      normalizedSupply = dripNormalizedSupply
      const receiveDripTx = await l2Reservoir.populateTransaction.receiveDrip(
        dripNormalizedSupply,
        dripIssuanceRate,
        toBN('0'),
      )
      const tx = await validGatewayFinalizeTransfer(receiveDripTx.data)
      dripBlock = await latestBlock()
      await expect(await l2Reservoir.issuanceBase()).to.eq(dripNormalizedSupply)
      await expect(await l2Reservoir.issuanceRate()).to.eq(dripIssuanceRate)
      await expect(tx).emit(l2Reservoir, 'DripReceived').withArgs(dripNormalizedSupply)
    })
    it('updates the normalized supply cache and issuance rate', async function () {
      normalizedSupply = dripNormalizedSupply
      let receiveDripTx = await l2Reservoir.populateTransaction.receiveDrip(
        dripNormalizedSupply,
        dripIssuanceRate,
        toBN('0'),
      )
      let tx = await validGatewayFinalizeTransfer(receiveDripTx.data)
      dripBlock = await latestBlock()
      await expect(await l2Reservoir.issuanceBase()).to.eq(dripNormalizedSupply)
      await expect(await l2Reservoir.issuanceRate()).to.eq(dripIssuanceRate)
      await expect(tx).emit(l2Reservoir, 'DripReceived').withArgs(dripNormalizedSupply)

      receiveDripTx = await l2Reservoir.populateTransaction.receiveDrip(
        dripNormalizedSupply.add(1),
        dripIssuanceRate.add(1),
        toBN('1'),
      )
      tx = await gatewayFinalizeTransfer(receiveDripTx.data)
      dripBlock = await latestBlock()
      await expect(await l2Reservoir.issuanceBase()).to.eq(dripNormalizedSupply.add(1))
      await expect(await l2Reservoir.issuanceRate()).to.eq(dripIssuanceRate.add(1))
      await expect(tx).emit(l2Reservoir, 'DripReceived').withArgs(dripNormalizedSupply.add(1))
      await expect(await grt.balanceOf(l2Reservoir.address)).to.eq(dripAmount.mul(2))
    })
    it('accepts subsequent calls without changing issuance rate', async function () {
      normalizedSupply = dripNormalizedSupply
      let receiveDripTx = await l2Reservoir.populateTransaction.receiveDrip(
        dripNormalizedSupply,
        dripIssuanceRate,
        toBN('0'),
      )
      let tx = await validGatewayFinalizeTransfer(receiveDripTx.data)
      dripBlock = await latestBlock()
      await expect(await l2Reservoir.issuanceBase()).to.eq(dripNormalizedSupply)
      await expect(await l2Reservoir.issuanceRate()).to.eq(dripIssuanceRate)
      await expect(tx).emit(l2Reservoir, 'DripReceived').withArgs(dripNormalizedSupply)

      receiveDripTx = await l2Reservoir.populateTransaction.receiveDrip(
        dripNormalizedSupply.add(1),
        dripIssuanceRate,
        toBN('1'),
      )
      tx = await gatewayFinalizeTransfer(receiveDripTx.data)
      dripBlock = await latestBlock()
      await expect(await l2Reservoir.issuanceBase()).to.eq(dripNormalizedSupply.add(1))
      await expect(await l2Reservoir.issuanceRate()).to.eq(dripIssuanceRate)
      await expect(tx).emit(l2Reservoir, 'DripReceived').withArgs(dripNormalizedSupply.add(1))
      await expect(await grt.balanceOf(l2Reservoir.address)).to.eq(dripAmount.mul(2))
    })
    it('accepts a different nonce set through setNextDripNonce', async function () {
      normalizedSupply = dripNormalizedSupply
      let receiveDripTx = await l2Reservoir.populateTransaction.receiveDrip(
        dripNormalizedSupply,
        dripIssuanceRate,
        toBN('0'),
      )
      let tx = await validGatewayFinalizeTransfer(receiveDripTx.data)
      dripBlock = await latestBlock()
      await expect(await l2Reservoir.issuanceBase()).to.eq(dripNormalizedSupply)
      await expect(await l2Reservoir.issuanceRate()).to.eq(dripIssuanceRate)
      await expect(tx).emit(l2Reservoir, 'DripReceived').withArgs(dripNormalizedSupply)

      await l2Reservoir.connect(governor.signer).setNextDripNonce(toBN('2'))
      receiveDripTx = await l2Reservoir.populateTransaction.receiveDrip(
        dripNormalizedSupply.add(1),
        dripIssuanceRate,
        toBN('2'),
      )
      tx = await gatewayFinalizeTransfer(receiveDripTx.data)
      dripBlock = await latestBlock()
      await expect(await l2Reservoir.issuanceBase()).to.eq(dripNormalizedSupply.add(1))
      await expect(await l2Reservoir.issuanceRate()).to.eq(dripIssuanceRate)
      await expect(tx).emit(l2Reservoir, 'DripReceived').withArgs(dripNormalizedSupply.add(1))
      await expect(await grt.balanceOf(l2Reservoir.address)).to.eq(dripAmount.mul(2))
    })
  })

  context('calculating rewards', async function () {
    beforeEach(async function () {
      // 5% minute rate (4 blocks)
      normalizedSupply = dripNormalizedSupply
      const receiveDripTx = await l2Reservoir.populateTransaction.receiveDrip(
        dripNormalizedSupply,
        ISSUANCE_RATE_PER_BLOCK,
        toBN('0'),
      )
      await validGatewayFinalizeTransfer(receiveDripTx.data)
      dripBlock = await latestBlock()
    })

    describe('getAccumulatedRewards', function () {
      it('returns rewards accrued after some blocks', async function () {
        await shouldGetNewRewards(normalizedSupply)
      })
      it('returns zero if evaluated at the block where reservoir had the first drip', async function () {
        await shouldGetNewRewards(
          normalizedSupply,
          ISSUANCE_RATE_PERIODS,
          dripBlock,
          toBN(0),
          false,
        )
      })
      it('returns the supply times issuance rate one block after the first drip', async function () {
        const expectedVal = normalizedSupply
          .mul(ISSUANCE_RATE_PER_BLOCK.sub(toGRT(1)))
          .div(toGRT(1))
        await shouldGetNewRewards(
          normalizedSupply,
          ISSUANCE_RATE_PERIODS,
          dripBlock.add(1),
          expectedVal,
          false,
        )
      })
      it('returns the rewards for a block some time in the future', async function () {
        await shouldGetNewRewards(normalizedSupply, toBN(1), dripBlock.add(10000))
      })
    })
    describe('getNewRewards', function () {
      const computeDelta = function (t1: BigNumber, t0: BigNumber, lambda = toBN(0)): BigNumber {
        const deltaT = new BN(t1.toString()).minus(new BN(t0.toString()))
        const rate = new BN(ISSUANCE_RATE_PER_BLOCK.toString()).div(1e18)
        const supply = new BN(normalizedSupply.toString())
        return toBN(supply.times(rate.pow(deltaT)).minus(supply).precision(18).toString(10))
          .mul(toGRT('1').sub(lambda))
          .div(toGRT('1'))
      }
      it('computes the rewards delta between the last drip block and the current block', async function () {
        const t0 = dripBlock
        const t1 = t0.add(200)
        const expectedVal = computeDelta(t1, t0)
        expect(toRound(await l2Reservoir.getNewRewards(t1))).to.eq(toRound(expectedVal))
      })
      it('returns zero rewards if the time delta is zero', async function () {
        const t0 = dripBlock
        const expectedVal = toBN('0')
        expect(await l2Reservoir.getNewRewards(t0)).to.eq(expectedVal)
      })
      it('computes the rewards delta between a past drip block and a future block', async function () {
        await advanceBlocks(20)
        const t0 = dripBlock
        const t1 = t0.add(100)
        const expectedVal = computeDelta(t1, t0)
        expect(toRound(await l2Reservoir.getNewRewards(t1))).to.eq(toRound(expectedVal))
      })
      it('computes the rewards delta between a past drip block and the current block', async function () {
        await advanceBlocks(20)
        const t0 = dripBlock
        const t1 = await latestBlock()
        const expectedVal = computeDelta(t1, t0)
        expect(toRound(await l2Reservoir.getNewRewards(t1))).to.eq(toRound(expectedVal))
      })
    })
  })
})
