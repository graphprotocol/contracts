import hre from 'hardhat'
import { expect } from 'chai'
import { BigNumber, constants, Contract, PopulatedTransaction } from 'ethers'

import { Curation } from '../../../build/types/Curation'
import { EpochManager } from '../../../build/types/EpochManager'
import { GraphToken } from '../../../build/types/GraphToken'
import { IStaking } from '../../../build/types/IStaking'
import { LibExponential } from '../../../build/types/LibExponential'

import { NetworkFixture } from '../lib/fixtures'
import {
  deriveChannelKey,
  GraphNetworkContracts,
  helpers,
  isGraphL1ChainId,
  randomHexBytes,
  toBN,
  toGRT,
} from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { IRewardsManager } from '../../../build/types'

const { AddressZero } = constants

const MAX_PPM = toBN('1000000')
const toPercentage = (ppm: BigNumber) => ppm.mul(100).div(MAX_PPM).toNumber()

enum AllocationState {
  Null,
  Active,
  Closed,
}

const ABI_LIB_EXPONENTIAL = [
  {
    inputs: [
      {
        internalType: 'uint256',
        name: 'fees',
        type: 'uint256',
      },
      {
        internalType: 'uint256',
        name: 'stake',
        type: 'uint256',
      },
      {
        internalType: 'uint32',
        name: 'alphaNumerator',
        type: 'uint32',
      },
      {
        internalType: 'uint32',
        name: 'alphaDenominator',
        type: 'uint32',
      },
      {
        internalType: 'uint32',
        name: 'lambdaNumerator',
        type: 'uint32',
      },
      {
        internalType: 'uint32',
        name: 'lambdaDenominator',
        type: 'uint32',
      },
    ],
    name: 'exponentialRebates',
    outputs: [
      {
        internalType: 'uint256',
        name: '',
        type: 'uint256',
      },
    ],
    stateMutability: 'pure',
    type: 'function',
  },
]

describe('Staking:Allocation', () => {
  const graph = hre.graph({ addressBook: 'addresses-local.json' })
  let me: SignerWithAddress
  let governor: SignerWithAddress
  let indexer: SignerWithAddress
  let delegator: SignerWithAddress
  let assetHolder: SignerWithAddress

  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts
  let curation: Curation
  let epochManager: EpochManager
  let grt: GraphToken
  let staking: IStaking
  let rewardsManager: IRewardsManager
  let libExponential: LibExponential

  // Test values

  const indexerTokens = toGRT('1000')
  const tokensToStake = toGRT('100')
  const tokensToDelegate = toGRT('10')
  const tokensToAllocate = toGRT('100')
  const tokensToCollect = toGRT('100')
  const subgraphDeploymentID = randomHexBytes()
  const channelKey = deriveChannelKey()
  const allocationID = channelKey.address
  const anotherChannelKey = deriveChannelKey()
  const anotherAllocationID = anotherChannelKey.address
  const metadata = randomHexBytes(32)
  const poi = randomHexBytes()

  // Helpers

  const allocate = async (tokens: BigNumber, _allocationID?: string, _proof?: string) => {
    return staking
      .connect(indexer)
      .allocateFrom(
        indexer.address,
        subgraphDeploymentID,
        tokens,
        _allocationID ?? allocationID,
        metadata,
        _proof ?? (await channelKey.generateProof(indexer.address)),
      )
  }

  const shouldAllocate = async (tokensToAllocate: BigNumber) => {
    // Advance epoch to prevent epoch jumping mid test
    await helpers.mineEpoch(epochManager)

    // Before state
    const beforeStake = await staking.stakes(indexer.address)

    // Allocate
    const currentEpoch = await epochManager.currentEpoch()
    const tx = allocate(tokensToAllocate)
    await expect(tx)
      .emit(staking, 'AllocationCreated')
      .withArgs(
        indexer.address,
        subgraphDeploymentID,
        currentEpoch,
        tokensToAllocate,
        allocationID,
        metadata,
      )

    // After state
    const afterStake = await staking.stakes(indexer.address)
    const afterAlloc = await staking.getAllocation(allocationID)
    const afterState = await staking.getAllocationState(allocationID)

    // Stake updated
    expect(afterStake.tokensAllocated).eq(beforeStake.tokensAllocated.add(tokensToAllocate))
    // Allocation updated
    expect(afterAlloc.indexer).eq(indexer.address)
    expect(afterAlloc.subgraphDeploymentID).eq(subgraphDeploymentID)
    expect(afterAlloc.tokens).eq(tokensToAllocate)
    expect(afterAlloc.createdAtEpoch).eq(currentEpoch)
    expect(afterAlloc.collectedFees).eq(toGRT('0'))
    expect(afterAlloc.closedAtEpoch).eq(toBN('0'))
    expect(afterState).to.eq(AllocationState.Active)
  }

  // This function tests collect with state updates
  const shouldCollect = async (
    tokensToCollect: BigNumber,
    options: {
      allocationID?: string
      expectEvent?: boolean
    } = {},
  ): Promise<{ queryRebates: BigNumber, queryFeesBurnt: BigNumber }> => {
    const expectEvent = options.expectEvent ?? true
    const alloID = options.allocationID ?? allocationID
    const alloStateBefore = await staking.getAllocationState(alloID)
    // Should have a particular state before collecting
    expect(alloStateBefore).to.be.oneOf([AllocationState.Active, AllocationState.Closed])

    // Before state
    const beforeTokenSupply = await grt.totalSupply()
    const beforePool = await curation.pools(subgraphDeploymentID)
    const beforeAlloc = await staking.getAllocation(alloID)
    const beforeIndexerBalance = await grt.balanceOf(indexer.address)
    const beforeStake = await staking.stakes(indexer.address)
    const beforeDelegationPool = await staking.delegationPools(indexer.address)

    // Advance blocks to get the allocation in epoch where it can be closed
    await helpers.mineEpoch(epochManager)

    // Collect fees and calculate expected results
    let rebateFees = tokensToCollect
    const protocolPercentage = await staking.protocolPercentage()
    const protocolFees = rebateFees.mul(protocolPercentage).div(MAX_PPM)
    rebateFees = rebateFees.sub(protocolFees)

    const curationPercentage = await staking.curationPercentage()
    const curationFees = rebateFees.mul(curationPercentage).div(MAX_PPM)
    rebateFees = rebateFees.sub(curationFees)

    const queryFees = tokensToCollect.sub(protocolFees).sub(curationFees)

    const [alphaNumerator, alphaDenominator, lambdaNumerator, lambdaDenominator]
      = await Promise.all([
        staking.alphaNumerator(),
        staking.alphaDenominator(),
        staking.lambdaNumerator(),
        staking.lambdaDenominator(),
      ])
    const accumulatedRebates = await libExponential.exponentialRebates(
      queryFees.add(beforeAlloc.collectedFees),
      beforeAlloc.tokens,
      alphaNumerator,
      alphaDenominator,
      lambdaNumerator,
      lambdaDenominator,
    )
    let queryRebates = beforeAlloc.distributedRebates.gt(accumulatedRebates)
      ? BigNumber.from(0)
      : accumulatedRebates.sub(beforeAlloc.distributedRebates)
    queryRebates = queryRebates.gt(queryFees) ? queryFees : queryRebates
    const queryFeesBurnt = queryFees.sub(queryRebates)

    const indexerCut = queryRebates.mul(beforeDelegationPool.queryFeeCut).div(MAX_PPM)
    const delegationRewards = queryRebates.sub(indexerCut)
    queryRebates = queryRebates.sub(delegationRewards)

    // Collect tokens from allocation
    const tx = staking.connect(assetHolder).collect(tokensToCollect, alloID)
    if (expectEvent) {
      await expect(tx)
        .emit(staking, 'RebateCollected')
        .withArgs(
          assetHolder.address,
          indexer.address,
          subgraphDeploymentID,
          alloID,
          await epochManager.currentEpoch(),
          tokensToCollect,
          protocolFees,
          curationFees,
          queryFees,
          queryRebates,
          delegationRewards,
        )
    } else {
      await expect(tx).to.not.be.reverted
      await expect(tx).to.not.emit(staking, 'RebateCollected')
    }

    // After state
    const afterTokenSupply = await grt.totalSupply()
    const afterPool = await curation.pools(subgraphDeploymentID)
    const afterAlloc = await staking.getAllocation(alloID)
    const afterIndexerBalance = await grt.balanceOf(indexer.address)
    const afterStake = await staking.stakes(indexer.address)
    const alloStateAfter = await staking.getAllocationState(alloID)

    // Check that protocol fees are burnt
    expect(afterTokenSupply).eq(beforeTokenSupply.sub(protocolFees).sub(queryFeesBurnt))

    // Check that collected tokens are correctly distributed for rebating + tax + curators
    // tokensToCollect = queryFees + protocolFees + curationFees
    expect(tokensToCollect).eq(queryFees.add(protocolFees).add(curationFees))

    // Check that queryFees are distributed
    // queryFees = queryRebates + queryFeesBurnt + delegationRewards
    expect(queryFees).eq(queryRebates.add(queryFeesBurnt).add(delegationRewards))

    // Check that curation reserves increased for the SubgraphDeployment
    expect(afterPool.tokens).eq(beforePool.tokens.add(curationFees))

    // Verify allocation struct
    expect(afterAlloc.tokens).eq(beforeAlloc.tokens)
    expect(afterAlloc.createdAtEpoch).eq(beforeAlloc.createdAtEpoch)
    expect(afterAlloc.closedAtEpoch).eq(beforeAlloc.closedAtEpoch)
    expect(afterAlloc.accRewardsPerAllocatedToken).eq(beforeAlloc.accRewardsPerAllocatedToken)
    expect(afterAlloc.collectedFees).eq(beforeAlloc.collectedFees.add(queryFees))
    expect(afterAlloc.distributedRebates).eq(
      beforeAlloc.distributedRebates.add(queryRebates).add(delegationRewards),
    )
    expect(alloStateAfter).eq(alloStateBefore)

    // // Funds distributed to indexer or restaked
    const restake = (await staking.rewardsDestination(indexer.address)) === AddressZero
    if (restake) {
      expect(afterIndexerBalance).eq(beforeIndexerBalance)
      // Next invariant is only true if there are no delegation rewards (which is true in this case)
      expect(afterStake.tokensStaked).eq(beforeStake.tokensStaked.add(queryRebates))
    } else {
      expect(afterIndexerBalance).eq(beforeIndexerBalance.add(queryRebates))
      expect(afterStake.tokensStaked).eq(beforeStake.tokensStaked)
    }

    return { queryRebates, queryFeesBurnt }
  }

  const shouldCollectMultiple = async (collections: BigNumber[]) => {
    // Perform the multiple collections on currently open allocation
    const totalTokensToCollect = collections.reduce((a, b) => a.add(b), BigNumber.from(0))
    let rebatedAmountMultiple = BigNumber.from(0)
    for (const collect of collections) {
      rebatedAmountMultiple = rebatedAmountMultiple.add((await shouldCollect(collect)).queryRebates)
    }

    // Reset rebates state by closing allocation, advancing epoch and opening a new allocation
    await staking.connect(indexer).closeAllocation(allocationID, poi)
    await helpers.mineEpoch(epochManager)
    await allocate(
      tokensToAllocate,
      anotherAllocationID,
      await anotherChannelKey.generateProof(indexer.address),
    )

    // Collect `tokensToCollect` with a single voucher
    const rebatedAmountFull = (
      await shouldCollect(totalTokensToCollect, { allocationID: anotherAllocationID })
    ).queryRebates

    // Check rebated amounts match, allow a small error margin of 5 wei
    // Due to rounding it's not possible to guarantee an exact match in case of multiple collections
    expect(rebatedAmountMultiple.sub(rebatedAmountFull)).lt(5)
  }

  const shouldCloseAllocation = async () => {
    // Before state
    const beforeStake = await staking.stakes(indexer.address)
    const beforeAlloc = await staking.getAllocation(allocationID)
    const beforeAlloState = await staking.getAllocationState(allocationID)
    expect(beforeAlloState).eq(AllocationState.Active)

    // Move at least one epoch to be able to close
    await helpers.mineEpoch(epochManager)
    await helpers.mineEpoch(epochManager)

    // Calculations
    const currentEpoch = await epochManager.currentEpoch()

    // Close allocation
    const tx = staking.connect(indexer).closeAllocation(allocationID, poi)
    await expect(tx)
      .emit(staking, 'AllocationClosed')
      .withArgs(
        indexer.address,
        subgraphDeploymentID,
        currentEpoch,
        beforeAlloc.tokens,
        allocationID,
        indexer.address,
        poi,
        false,
      )

    // After state
    const afterStake = await staking.stakes(indexer.address)
    const afterAlloc = await staking.getAllocation(allocationID)
    const afterAlloState = await staking.getAllocationState(allocationID)

    // Stake updated
    expect(afterStake.tokensAllocated).eq(beforeStake.tokensAllocated.sub(beforeAlloc.tokens))
    // Allocation updated
    expect(afterAlloc.closedAtEpoch).eq(currentEpoch)
    // State progressed
    expect(afterAlloState).eq(AllocationState.Closed)
  }
  // -- Tests --

  before(async function () {
    [me, indexer, delegator, assetHolder] = await graph.getTestAccounts()
    ;({ governor } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
    curation = contracts.Curation as Curation
    epochManager = contracts.EpochManager
    grt = contracts.GraphToken as GraphToken
    staking = contracts.Staking as IStaking
    rewardsManager = contracts.RewardsManager as IRewardsManager

    const stakingName = isGraphL1ChainId(graph.chainId) ? 'L1Staking' : 'L2Staking'
    const entry = graph.addressBook.getEntry(stakingName)

    libExponential = new Contract(
      entry.implementation.libraries.LibExponential,
      ABI_LIB_EXPONENTIAL,
      graph.provider,
    ) as LibExponential

    // Give some funds to the indexer and approve staking contract to use funds on indexer behalf
    await grt.connect(governor).mint(indexer.address, indexerTokens)
    await grt.connect(indexer).approve(staking.address, indexerTokens)

    // Give some funds to the delegator and approve staking contract to use funds on delegator behalf
    await grt.connect(governor).mint(delegator.address, tokensToDelegate)
    await grt.connect(delegator).approve(staking.address, tokensToDelegate)
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('operators', function () {
    it('should set operator', async function () {
      // Before state
      const beforeOperator = await staking.operatorAuth(indexer.address, me.address)

      // Set operator
      const tx = staking.connect(indexer).setOperator(me.address, true)
      await expect(tx).emit(staking, 'SetOperator').withArgs(indexer.address, me.address, true)

      // After state
      const afterOperator = await staking.operatorAuth(indexer.address, me.address)

      // State updated
      expect(beforeOperator).eq(false)
      expect(afterOperator).eq(true)
    })

    it('should unset operator', async function () {
      await staking.connect(indexer).setOperator(me.address, true)

      // Before state
      const beforeOperator = await staking.operatorAuth(indexer.address, me.address)

      // Set operator
      const tx = staking.connect(indexer).setOperator(me.address, false)
      await expect(tx).emit(staking, 'SetOperator').withArgs(indexer.address, me.address, false)

      // After state
      const afterOperator = await staking.operatorAuth(indexer.address, me.address)

      // State updated
      expect(beforeOperator).eq(true)
      expect(afterOperator).eq(false)
    })
    it('should reject setting the operator to the msg.sender', async function () {
      await expect(staking.connect(indexer).setOperator(indexer.address, true)).to.be.revertedWith(
        'operator == sender',
      )
    })
  })

  describe('rewardsDestination', function () {
    it('should set rewards destination', async function () {
      // Before state
      const beforeDestination = await staking.rewardsDestination(indexer.address)

      // Set
      const tx = staking.connect(indexer).setRewardsDestination(me.address)
      await expect(tx).emit(staking, 'SetRewardsDestination').withArgs(indexer.address, me.address)

      // After state
      const afterDestination = await staking.rewardsDestination(indexer.address)

      // State updated
      expect(beforeDestination).eq(AddressZero)
      expect(afterDestination).eq(me.address)

      // Must be able to set back to zero
      await staking.connect(indexer).setRewardsDestination(AddressZero)
      expect(await staking.rewardsDestination(indexer.address)).eq(AddressZero)
    })
  })

  /**
   * Allocate
   */
  describe('allocate', function () {
    it('reject allocate with invalid allocationID', async function () {
      const tx = staking
        .connect(indexer)
        .allocateFrom(
          indexer.address,
          subgraphDeploymentID,
          tokensToAllocate,
          AddressZero,
          metadata,
          randomHexBytes(20),
        )
      await expect(tx).revertedWith('!alloc')
    })

    it('reject allocate if no tokens staked', async function () {
      const tx = allocate(toBN('1'))
      await expect(tx).revertedWith('!minimumIndexerStake')
    })

    it('reject allocate zero tokens if no minimum stake', async function () {
      const tx = allocate(toBN('0'))
      await expect(tx).revertedWith('!minimumIndexerStake')
    })

    context('> when staked', function () {
      beforeEach(async function () {
        await staking.connect(indexer).stake(tokensToStake)
      })

      it('reject allocate more than available tokens', async function () {
        const tokensOverCapacity = tokensToStake.add(toBN('1'))
        const tx = allocate(tokensOverCapacity)
        await expect(tx).revertedWith('!capacity')
      })

      it('should allocate', async function () {
        await helpers.mineEpoch(epochManager)
        await shouldAllocate(tokensToAllocate)
      })

      it('should allow allocation of zero tokens', async function () {
        const zeroTokens = toGRT('0')
        const tx = allocate(zeroTokens)
        await tx
      })

      it('should allocate on behalf of indexer', async function () {
        const proof = await channelKey.generateProof(indexer.address)

        // Reject to allocate if the address is not operator
        const tx1 = staking
          .connect(me)
          .allocateFrom(
            indexer.address,
            subgraphDeploymentID,
            tokensToAllocate,
            allocationID,
            metadata,
            proof,
          )
        await expect(tx1).revertedWith('!auth')

        // Should allocate if given operator auth
        await staking.connect(indexer).setOperator(me.address, true)
        await staking
          .connect(me)
          .allocateFrom(
            indexer.address,
            subgraphDeploymentID,
            tokensToAllocate,
            allocationID,
            metadata,
            proof,
          )
      })

      it('reject allocate reusing an allocation ID', async function () {
        await helpers.mineEpoch(epochManager)
        const someTokensToAllocate = toGRT('10')
        await shouldAllocate(someTokensToAllocate)
        const tx = allocate(someTokensToAllocate)
        await expect(tx).revertedWith('!null')
      })

      describe('reject allocate on invalid proof', function () {
        it('invalid message', async function () {
          const invalidProof = await channelKey.generateProof(randomHexBytes(20))
          const tx = staking
            .connect(indexer)
            .allocateFrom(
              indexer.address,
              subgraphDeploymentID,
              tokensToAllocate,
              indexer.address,
              metadata,
              invalidProof,
            )
          await expect(tx).revertedWith('!proof')
        })

        it('invalid proof signature format', async function () {
          const tx = staking
            .connect(indexer)
            .allocateFrom(
              indexer.address,
              subgraphDeploymentID,
              tokensToAllocate,
              indexer.address,
              metadata,
              randomHexBytes(32),
            )
          await expect(tx).revertedWith('ECDSA: invalid signature length')
        })
      })
    })
  })

  /**
   * Collect
   */
  describe('collect', function () {
    beforeEach(async function () {
      // Create the allocation
      await staking.connect(indexer).stake(tokensToStake)
      await helpers.mineEpoch(epochManager)
      await allocate(tokensToAllocate)

      // Add some signal to the subgraph to enable curation fees
      const tokensToSignal = toGRT('100')
      await grt.connect(governor).mint(me.address, tokensToSignal)
      await grt.connect(me).approve(curation.address, tokensToSignal)
      await curation.connect(me).mint(subgraphDeploymentID, tokensToSignal, 0)

      // Fund asset holder wallet
      const tokensToFund = toGRT('100000')
      await grt.connect(governor).mint(assetHolder.address, tokensToFund)
      await grt.connect(assetHolder).approve(staking.address, tokensToFund)
    })

    // * Test with different curation fees and protocol tax
    for (const params of [
      { curationPercentage: toBN('0'), protocolPercentage: toBN('0'), queryFeeCut: toBN('0') },
      { curationPercentage: toBN('0'), protocolPercentage: toBN('100000'), queryFeeCut: toBN('0') },
      { curationPercentage: toBN('200000'), protocolPercentage: toBN('0'), queryFeeCut: toBN('0') },
      {
        curationPercentage: toBN('200000'),
        protocolPercentage: toBN('100000'),
        queryFeeCut: toBN('950000'),
      },
    ]) {
      context(
        `> with ${toPercentage(params.curationPercentage)}% curationFees, ${toPercentage(
          params.protocolPercentage,
        )}% protocolTax and ${toPercentage(params.queryFeeCut)}% queryFeeCut`,
        function () {
          beforeEach(async function () {
            // Set a protocol fee percentage
            await staking.connect(governor).setProtocolPercentage(params.protocolPercentage)

            // Set a curation fee percentage
            await staking.connect(governor).setCurationPercentage(params.curationPercentage)

            // Setup delegation
            await staking.connect(governor).setDelegationRatio(10) // 1:10 delegation capacity
            await staking
              .connect(indexer)
              .setDelegationParameters(toBN('800000'), params.queryFeeCut, 5)
            await staking.connect(delegator).delegate(indexer.address, tokensToDelegate)
          })

          it('should collect funds from asset holder (restake=true)', async function () {
            await shouldCollect(tokensToCollect)
          })

          it('should collect funds from asset holder (restake=false)', async function () {
            // Set a random rewards destination address
            await staking.connect(governor).setRewardsDestination(me.address)
            await shouldCollect(tokensToCollect)
          })

          it('should collect funds on both active and closed allocations', async function () {
            // Collect from active allocation
            await shouldCollect(tokensToCollect)

            // Close allocation
            await staking.connect(indexer).closeAllocation(allocationID, poi)

            // Collect from closed allocation
            await shouldCollect(tokensToCollect)
          })

          it('should collect zero tokens', async function () {
            await shouldCollect(toGRT('0'), { expectEvent: false })
          })

          it('should allow multiple collections on the same allocation', async function () {
            // Collect `tokensToCollect` with 4 different vouchers
            // This can represent vouchers not necessarily from the same gateway
            const splitCollect = tokensToCollect.div(4)
            await shouldCollectMultiple(Array(4).fill(splitCollect))
          })

          it('should allow multiple collections on the same allocation (edge case 1: small then big)', async function () {
            // Collect `tokensToCollect` with 2 vouchers, one small and then one big
            const smallCollect = tokensToCollect.div(100)
            const bigCollect = tokensToCollect.sub(smallCollect)
            await shouldCollectMultiple([smallCollect, bigCollect])
          })

          it('should allow multiple collections on the same allocation (edge case 2: big then small)', async function () {
            // Collect `tokensToCollect` with 2 vouchers, one big and then one small
            const smallCollect = tokensToCollect.div(100)
            const bigCollect = tokensToCollect.sub(smallCollect)
            await shouldCollectMultiple([bigCollect, smallCollect])
          })
        },
      )
    }

    it('reject collect if invalid collection', async function () {
      const tx = staking.connect(indexer).collect(tokensToCollect, AddressZero)
      await expect(tx).revertedWith('!alloc')
    })

    it('reject collect if allocation does not exist', async function () {
      const invalidAllocationID = randomHexBytes(20)
      const tx = staking.connect(assetHolder).collect(tokensToCollect, invalidAllocationID)
      await expect(tx).revertedWith('!collect')
    })

    it('should get no rebates if allocated stake is zero', async function () {
      // Create an allocation with no stake
      await staking.connect(indexer).stake(tokensToStake)
      await allocate(
        BigNumber.from(0),
        anotherAllocationID,
        await anotherChannelKey.generateProof(indexer.address),
      )

      // Collect from closed allocation, should get no rebates
      const rebates = await shouldCollect(tokensToCollect, { allocationID: anotherAllocationID })
      expect(rebates.queryRebates).eq(BigNumber.from(0))
      expect(rebates.queryFeesBurnt).eq(tokensToCollect)
    })

    it('should resolve over-rebated scenarios correctly', async function () {
      // Set up a new allocation with `tokensToAllocate` staked
      await staking.connect(indexer).stake(tokensToStake)
      await allocate(
        tokensToAllocate,
        anotherAllocationID,
        await anotherChannelKey.generateProof(indexer.address),
      )

      // Set initial rebate parameters, α = 0, λ = 1
      await staking.connect(governor).setRebateParameters(0, 1, 1, 1)

      // Collection amounts
      const firstTokensToCollect = tokensToAllocate.mul(8).div(10) // q1 < sij
      const secondTokensToCollect = tokensToAllocate.div(10) // q2 small amount, second collect should get "negative rebates"
      const thirdTokensToCollect = tokensToAllocate.mul(3) // q3 big amount so we get rebates again

      // First collection
      // Indexer gets 100% of the query fees due to α = 0
      const firstRebates = await shouldCollect(firstTokensToCollect, {
        allocationID: anotherAllocationID,
      })
      expect(firstRebates.queryRebates).eq(firstTokensToCollect)
      expect(firstRebates.queryFeesBurnt).eq(BigNumber.from(0))

      // Update rebate parameters, α = 1, λ = 1
      await staking.connect(governor).setRebateParameters(1, 1, 1, 1)

      // Second collection
      // Indexer gets 0% of the query fees
      // Parameters changed so now they are over-rebated and should get "negative rebates", instead they get 0
      const secondRebates = await shouldCollect(secondTokensToCollect, {
        allocationID: anotherAllocationID,
      })
      expect(secondRebates.queryRebates).eq(BigNumber.from(0))
      expect(secondRebates.queryFeesBurnt).eq(secondTokensToCollect)

      // Third collection
      // Previous collection plus this new one tip the balance and indexer is no longer over-rebated
      // They get rebates and burn again
      const thirdRebates = await shouldCollect(thirdTokensToCollect, {
        allocationID: anotherAllocationID,
      })
      expect(thirdRebates.queryRebates).gt(BigNumber.from(0))
      expect(thirdRebates.queryFeesBurnt).gt(BigNumber.from(0))
    })

    it('should resolve under-rebated scenarios correctly', async function () {
      // Set up a new allocation with `tokensToAllocate` staked
      await staking.connect(indexer).stake(tokensToStake)
      await allocate(
        tokensToAllocate,
        anotherAllocationID,
        await anotherChannelKey.generateProof(indexer.address),
      )

      // Set initial rebate parameters, α = 1, λ = 1
      await staking.connect(governor).setRebateParameters(1, 1, 1, 1)

      // Collection amounts
      const firstTokensToCollect = tokensToAllocate
      const secondTokensToCollect = tokensToAllocate
      const thirdTokensToCollect = tokensToAllocate.mul(50)

      // First collection
      // Indexer gets rebates and burn
      const firstRebates = await shouldCollect(firstTokensToCollect, {
        allocationID: anotherAllocationID,
      })
      expect(firstRebates.queryRebates).gt(BigNumber.from(0))
      expect(firstRebates.queryFeesBurnt).gt(BigNumber.from(0))

      // Update rebate parameters, α = 0.1, λ = 1
      await staking.connect(governor).setRebateParameters(1, 10, 1, 1)

      // Second collection
      // Indexer gets 100% of the query fees
      // Parameters changed so now they are under-rebated and should get more than the available amount but we cap it
      const secondRebates = await shouldCollect(secondTokensToCollect, {
        allocationID: anotherAllocationID,
      })
      expect(secondRebates.queryRebates).eq(secondTokensToCollect)
      expect(secondRebates.queryFeesBurnt).eq(BigNumber.from(0))

      // Third collection
      // Previous collection plus this new one tip the balance and indexer is no longer under-rebated
      // They get rebates and burn again
      const thirdRebates = await shouldCollect(thirdTokensToCollect, {
        allocationID: anotherAllocationID,
      })
      expect(thirdRebates.queryRebates).gt(BigNumber.from(0))
      expect(thirdRebates.queryFeesBurnt).gt(BigNumber.from(0))
    })

    it('should collect zero tokens', async function () {
      await shouldCollect(toGRT('0'), { expectEvent: false })
    })

    it('should get stuck under-rebated if alpha is changed to zero', async function () {
      // Set up a new allocation with `tokensToAllocate` staked
      await staking.connect(indexer).stake(tokensToStake)
      await allocate(
        tokensToAllocate,
        anotherAllocationID,
        await anotherChannelKey.generateProof(indexer.address),
      )

      // Set initial rebate parameters, α = 1, λ = 1
      await staking.connect(governor).setRebateParameters(1, 1, 1, 1)

      // First collection
      // Indexer gets rebates and burn
      const firstRebates = await shouldCollect(tokensToCollect, {
        allocationID: anotherAllocationID,
      })
      expect(firstRebates.queryRebates).gt(BigNumber.from(0))
      expect(firstRebates.queryFeesBurnt).gt(BigNumber.from(0))

      // Update rebate parameters, α = 0, λ = 1
      await staking.connect(governor).setRebateParameters(0, 1, 1, 1)

      // Successive collections
      // Indexer gets 100% of the query fees
      // Parameters changed so now they are under-rebated and should get more than the available amount but we cap it
      // Distributed amount will never catch up due to the initial collection which was less than 100%
      for (const _i of [...Array(10).keys()]) {
        const succesiveRebates = await shouldCollect(tokensToCollect, {
          allocationID: anotherAllocationID,
        })
        expect(succesiveRebates.queryRebates).eq(tokensToCollect)
        expect(succesiveRebates.queryFeesBurnt).eq(BigNumber.from(0))
      }
    })
  })

  /**
   * Close allocation
   */
  describe('closeAllocation', function () {
    beforeEach(async function () {
      // Stake and allocate
      await staking.connect(indexer).stake(tokensToStake)
    })

    for (const tokensToAllocate of [toBN(100), toBN(0)]) {
      context(`> with ${tokensToAllocate.toString()} allocated tokens`, function () {
        beforeEach(async function () {
          // Advance to next epoch to avoid creating the allocation
          // right at the epoch boundary, which would mess up the tests.
          await helpers.mineEpoch(epochManager)

          // Allocate
          await allocate(tokensToAllocate)
        })

        it('reject close a non-existing allocation', async function () {
          const invalidAllocationID = randomHexBytes(20)
          const tx = staking.connect(indexer).closeAllocation(invalidAllocationID, poi)
          await expect(tx).revertedWith('!active')
        })

        it('allow close before one epoch has passed', async function () {
          const currentEpoch = await epochManager.currentEpoch()
          const beforeAlloc = await staking.getAllocation(allocationID)

          const tx = staking.connect(indexer).closeAllocation(allocationID, poi)
          await expect(tx)
            .emit(staking, 'AllocationClosed')
            .withArgs(
              indexer.address,
              subgraphDeploymentID,
              currentEpoch,
              beforeAlloc.tokens,
              allocationID,
              indexer.address,
              poi,
              false,
            )
          await expect(tx).not.to.emit(rewardsManager, 'RewardsAssigned')
        })

        it('reject close if not the owner of allocation', async function () {
          // Move at least one epoch to be able to close
          await helpers.mineEpoch(epochManager)

          // Close allocation
          const tx = staking.connect(me).closeAllocation(allocationID, poi)
          await expect(tx).revertedWith('!auth')
        })

        it('reject close if allocation is already closed', async function () {
          // Move at least one epoch to be able to close
          await helpers.mineEpoch(epochManager)

          // First closing
          await staking.connect(indexer).closeAllocation(allocationID, poi)

          // Second closing
          const tx = staking.connect(indexer).closeAllocation(allocationID, poi)
          await expect(tx).revertedWith('!active')
        })

        it('should close an allocation', async function () {
          await shouldCloseAllocation()
        })

        it('should close an allocation (by operator)', async function () {
          // Move at least one epoch to be able to close
          await helpers.mineEpoch(epochManager)
          await helpers.mineEpoch(epochManager)

          // Reject to close if the address is not operator
          const tx1 = staking.connect(me).closeAllocation(allocationID, poi)
          await expect(tx1).revertedWith('!auth')

          // Should close if given operator auth
          await staking.connect(indexer).setOperator(me.address, true)
          await staking.connect(me).closeAllocation(allocationID, poi)
        })

        it('should close an allocation (by public) only if allocation is non-zero', async function () {
          // Reject to close if public address and under max allocation epochs
          const tx1 = staking.connect(me).closeAllocation(allocationID, poi)
          await expect(tx1).revertedWith('!auth')

          // Move max allocation epochs to close by delegator
          const maxAllocationEpochs = await staking.maxAllocationEpochs()
          await helpers.mineEpoch(epochManager, maxAllocationEpochs + 1)

          // Closing should only be possible if allocated tokens > 0
          const alloc = await staking.getAllocation(allocationID)
          if (alloc.tokens.gt(0)) {
            // Calculations
            const beforeAlloc = await staking.getAllocation(allocationID)
            const currentEpoch = await epochManager.currentEpoch()

            // Setup
            await grt.connect(governor).mint(me.address, toGRT('1'))
            await grt.connect(me).approve(staking.address, toGRT('1'))

            // Should close by public
            const tx = staking.connect(me).closeAllocation(allocationID, poi)
            await expect(tx)
              .emit(staking, 'AllocationClosed')
              .withArgs(
                indexer.address,
                subgraphDeploymentID,
                currentEpoch,
                beforeAlloc.tokens,
                allocationID,
                me.address,
                poi,
                true,
              )
          } else {
            // closing by the public on a zero allocation is not authorized
            const tx = staking.connect(me).closeAllocation(allocationID, poi)
            await expect(tx).revertedWith('!auth')
          }
        })

        it('should close many allocations in batch', async function () {
          // Setup a second allocation
          await staking.connect(indexer).stake(tokensToStake)
          const channelKey2 = deriveChannelKey()
          const allocationID2 = channelKey2.address
          await staking
            .connect(indexer)
            .allocate(
              subgraphDeploymentID,
              tokensToAllocate,
              allocationID2,
              metadata,
              await channelKey2.generateProof(indexer.address),
            )

          // Move at least one epoch to be able to close
          await helpers.mineEpoch(epochManager)
          await helpers.mineEpoch(epochManager)

          // Close multiple allocations in one tx
          const requests = await Promise.all(
            [
              {
                allocationID: allocationID,
                poi: poi,
              },
              {
                allocationID: allocationID2,
                poi: poi,
              },
            ].map(({ allocationID, poi }) =>
              staking.connect(indexer).populateTransaction.closeAllocation(allocationID, poi),
            ),
          ).then(e => e.map((e: PopulatedTransaction) => e.data))
          await staking.connect(indexer).multicall(requests)
        })
      })
    }
  })

  describe('closeAndAllocate', function () {
    beforeEach(async function () {
      // Stake and allocate
      await staking.connect(indexer).stake(tokensToAllocate)
      await allocate(tokensToAllocate)
    })

    it('should close and create a new allocation', async function () {
      // Move at least one epoch to be able to close
      await helpers.mineEpoch(epochManager)

      // Close and allocate
      const newChannelKey = deriveChannelKey()
      const newAllocationID = newChannelKey.address

      // Close multiple allocations in one tx
      const requests = await Promise.all([
        staking.connect(indexer).populateTransaction.closeAllocation(allocationID, poi),
        staking
          .connect(indexer)
          .populateTransaction.allocateFrom(
            indexer.address,
            subgraphDeploymentID,
            tokensToAllocate,
            newAllocationID,
            metadata,
            await newChannelKey.generateProof(indexer.address),
          ),
      ]).then(e => e.map((e: PopulatedTransaction) => e.data))
      await staking.connect(indexer).multicall(requests)
    })
  })
})
