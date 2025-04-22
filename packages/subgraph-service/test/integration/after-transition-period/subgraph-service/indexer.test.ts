import { ethers } from 'hardhat'
import { expect } from 'chai'
import { HDNodeWallet } from 'ethers'
import hre from 'hardhat'

import { encodeCollectData, encodeStartServiceData, generateAllocationProof, generatePOI, getSignedRAVCalldata, getSignerProof, PaymentTypes } from '@graphprotocol/toolshed'
import { GraphPayments, GraphTallyCollector, HorizonStaking } from '@graphprotocol/horizon'
import { IGraphToken, IPaymentsEscrow, SubgraphService } from '../../../../typechain-types'
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { setGRTBalance } from '@graphprotocol/toolshed/hardhat'

import { Indexer, indexers } from '../../../../tasks/test/fixtures/indexers'
import { delegators } from '@graphprotocol/horizon/tasks/test/fixtures/delegators'

describe('Indexer', () => {
  let escrow: IPaymentsEscrow
  let graphPayments: GraphPayments
  let graphTallyCollector: GraphTallyCollector
  let graphToken: IGraphToken
  let staking: HorizonStaking
  let subgraphService: SubgraphService

  let snapshotId: string
  let chainId: number

  // Test addresses
  let indexer: HardhatEthersSigner
  let graphTallyCollectorAddress: string
  let subgraphServiceAddress: string

  const graph = hre.graph()
  const { collect } = graph.subgraphService.actions

  before(async () => {
    // Get contracts
    escrow = graph.horizon.contracts.PaymentsEscrow
    graphPayments = graph.horizon.contracts.GraphPayments
    graphTallyCollector = graph.horizon.contracts.GraphTallyCollector
    graphToken = graph.horizon.contracts.GraphToken
    staking = graph.horizon.contracts.HorizonStaking
    subgraphService = graph.subgraphService.contracts.SubgraphService

    // Get contract addresses
    graphTallyCollectorAddress = await graphTallyCollector.getAddress()
    subgraphServiceAddress = await subgraphService.getAddress()

    // Get chain ID
    chainId = Number((await ethers.provider.getNetwork()).chainId)
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe('Indexer Registration', () => {
    let indexerUrl: string
    let indexerGeoHash: string

    beforeEach(async () => {
      const indexerFixture = indexers[0]
      indexer = await ethers.getSigner(indexerFixture.address)
      indexerUrl = indexerFixture.url
      indexerGeoHash = indexerFixture.geoHash
    })

    it('should register indexer with valid parameters', async () => {
      // Verify indexer metadata
      const indexerInfo = await subgraphService.indexers(indexer.address)
      expect(indexerInfo.url).to.equal(indexerUrl)
      expect(indexerInfo.geoHash).to.equal(indexerGeoHash)
    })
  })

  describe('Allocation Management', () => {
    let allocationId: string
    let allocationPrivateKey: string
    let allocationTokens: bigint
    let subgraphDeploymentId: string
    let indexerFixture: Indexer

    before(async () => {
      // Get indexer data
      indexerFixture = indexers[0]
      indexer = await ethers.getSigner(indexerFixture.address)
    })

    describe('New allocation', () => {
      let provisionTokens: bigint

      before(() => {
        // Generate new allocation ID and private key
        const wallet = ethers.Wallet.createRandom()
        allocationId = wallet.address
        allocationPrivateKey = wallet.privateKey
        allocationTokens = ethers.parseEther('1000')
        subgraphDeploymentId = indexerFixture.allocations[0].subgraphDeploymentID

        // Get provision tokens
        provisionTokens = indexerFixture.provisionTokens
      })

      it('should start an allocation with valid parameters', async () => {
        // Get locked tokens before allocation
        const beforeLockedTokens = await subgraphService.allocationProvisionTracker(indexer.address)

        // Build allocation proof
        const signature = await generateAllocationProof(indexer.address, allocationPrivateKey, subgraphServiceAddress, chainId)

        // Attempt to create an allocation with the same ID
        const data = encodeStartServiceData(subgraphDeploymentId, allocationTokens, allocationId, signature)

        // Start allocation
        await subgraphService.connect(indexer).startService(
          indexer.address,
          data,
        )

        // Verify allocation
        const allocation = await subgraphService.getAllocation(allocationId)
        expect(allocation.indexer).to.equal(indexer.address, 'Allocation indexer is not the expected indexer')
        expect(allocation.tokens).to.equal(allocationTokens, 'Allocation tokens are not the expected tokens')
        expect(allocation.subgraphDeploymentId).to.equal(subgraphDeploymentId, 'Allocation subgraph deployment ID is not the expected subgraph deployment ID')

        // Verify tokens are locked
        const afterLockedTokens = await subgraphService.allocationProvisionTracker(indexer.address)
        expect(afterLockedTokens).to.equal(beforeLockedTokens + allocationTokens)
      })

      it('should be able to start an allocation with zero tokens', async () => {
        // Build allocation proof
        const signature = await generateAllocationProof(indexer.address, allocationPrivateKey, subgraphServiceAddress, chainId)

        // Attempt to create an allocation with the same ID
        const data = encodeStartServiceData(subgraphDeploymentId, 0n, allocationId, signature)

        // Start allocation with zero tokens
        await subgraphService.connect(indexer).startService(
          indexer.address,
          data,
        )

        // Verify allocation
        const allocation = await subgraphService.getAllocation(allocationId)
        expect(allocation.indexer).to.equal(indexer.address, 'Allocation indexer is not the expected indexer')
        expect(allocation.tokens).to.equal(0, 'Allocation tokens are not zero')
        expect(allocation.subgraphDeploymentId).to.equal(subgraphDeploymentId, 'Allocation subgraph deployment ID is not the expected subgraph deployment ID')
      })

      it('should not start an allocation without enough tokens', async () => {
        // Build allocation proof
        const signature = await generateAllocationProof(indexer.address, allocationPrivateKey, subgraphServiceAddress, chainId)

        // Build allocation data
        const allocationTokens = provisionTokens + ethers.parseEther('10000000')
        const data = encodeStartServiceData(subgraphDeploymentId, allocationTokens, allocationId, signature)

        // Attempt to open allocation with excessive tokens
        await expect(
          subgraphService.connect(indexer).startService(
            indexer.address,
            data,
          ),
        ).to.be.revertedWithCustomError(
          subgraphService,
          'ProvisionTrackerInsufficientTokens',
        )
      })
    })

    describe('Existing allocation', () => {
      beforeEach(() => {
        // Get allocation data
        const allocation = indexerFixture.allocations[0]
        allocationId = allocation.allocationID
        allocationTokens = allocation.tokens
        subgraphDeploymentId = allocation.subgraphDeploymentID
      })

      describe('Resize allocation', () => {
        it('should resize an open allocation increasing tokens', async () => {
          // Get locked tokens before resize
          const beforeLockedTokens = await subgraphService.allocationProvisionTracker(indexer.address)

          // Resize allocation
          const increaseTokens = ethers.parseEther('5000')
          const newAllocationTokens = allocationTokens + increaseTokens
          await subgraphService.connect(indexer).resizeAllocation(
            indexer.address,
            allocationId,
            newAllocationTokens,
          )

          // Verify allocation
          const allocation = await subgraphService.getAllocation(allocationId)
          expect(allocation.tokens).to.equal(newAllocationTokens, 'Allocation tokens were not resized')

          // Verify tokens are locked
          const afterLockedTokens = await subgraphService.allocationProvisionTracker(indexer.address)
          expect(afterLockedTokens).to.equal(beforeLockedTokens + increaseTokens)
        })

        it('should resize an open allocation decreasing tokens', async () => {
          // Get locked tokens before resize
          const beforeLockedTokens = await subgraphService.allocationProvisionTracker(indexer.address)

          // Resize allocation
          const decreaseTokens = ethers.parseEther('5000')
          const newAllocationTokens = allocationTokens - decreaseTokens
          await subgraphService.connect(indexer).resizeAllocation(
            indexer.address,
            allocationId,
            newAllocationTokens,
          )

          // Verify allocation
          const allocation = await subgraphService.getAllocation(allocationId)
          expect(allocation.tokens).to.equal(newAllocationTokens)

          // Verify tokens are released
          const afterLockedTokens = await subgraphService.allocationProvisionTracker(indexer.address)
          expect(afterLockedTokens).to.equal(beforeLockedTokens - decreaseTokens)
        })
      })

      describe('Close allocation', () => {
        it('should be able to close an allocation', async () => {
          // Get before locked tokens
          const beforeLockedTokens = await subgraphService.allocationProvisionTracker(indexer.address)

          // Close allocation
          const data = ethers.AbiCoder.defaultAbiCoder().encode(
            ['address'],
            [allocationId],
          )
          await subgraphService.connect(indexer).stopService(indexer.address, data)

          // Verify allocation is closed
          const allocation = await subgraphService.getAllocation(allocationId)
          expect(allocation.closedAt).to.not.equal(0)

          // Verify tokens are released
          const afterLockedTokens = await subgraphService.allocationProvisionTracker(indexer.address)
          expect(afterLockedTokens).to.equal(beforeLockedTokens - allocationTokens)
        })
      })
    })
  })

  describe('Indexing Rewards', () => {
    let allocationId: string

    describe('Re-provisioning', () => {
      let otherAllocationId: string

      beforeEach(async () => {
        // Get indexer
        const indexerFixture = indexers[0]
        indexer = await ethers.getSigner(indexerFixture.address)

        // Get allocations
        allocationId = indexerFixture.allocations[0].allocationID
        otherAllocationId = indexerFixture.allocations[1].allocationID

        // Check rewards destination is not set
        const rewardsDestination = await subgraphService.rewardsDestination(indexer.address)
        expect(rewardsDestination).to.equal(ethers.ZeroAddress, 'Rewards destination should be zero address')
      })

      it('should collect indexing rewards with re-provisioning', async () => {
        // Get before provision tokens
        const beforeProvisionTokens = (await staking.getProvision(indexer.address, subgraphService.target)).tokens

        // Mine multiple blocks to simulate time passing
        for (let i = 0; i < 1000; i++) {
          await ethers.provider.send('evm_mine', [])
        }

        // Build data for collect indexing rewards
        const poi = generatePOI()
        const data = encodeCollectData(allocationId, poi)

        // Collect rewards
        const rewards = await collect(indexer, [indexer.address, PaymentTypes.IndexingRewards, data])
        expect(rewards).to.not.equal(0n, 'Rewards should be greater than zero')

        // Verify rewards are added to provision
        const afterProvisionTokens = (await staking.getProvision(indexer.address, subgraphService.target)).tokens
        expect(afterProvisionTokens).to.equal(beforeProvisionTokens + rewards, 'Rewards should be collected')
      })

      it('should collect rewards continuously for multiple allocations', async () => {
        // Get before provision tokens
        const beforeProvisionTokens = (await staking.getProvision(indexer.address, subgraphService.target)).tokens

        // Build data for collect indexing rewards
        const poi = generatePOI()
        const allocationData = encodeCollectData(allocationId, poi)
        const otherAllocationData = encodeCollectData(otherAllocationId, poi)

        // Mine multiple blocks to simulate time passing
        for (let i = 0; i < 1000; i++) {
          await ethers.provider.send('evm_mine', [])
        }

        // Collect rewards for first allocation
        let rewards = await collect(indexer, [indexer.address, PaymentTypes.IndexingRewards, allocationData])
        expect(rewards).to.not.equal(0n, 'Rewards should be greater than zero')

        // Collect rewards for second allocation
        let otherRewards = await collect(indexer, [indexer.address, PaymentTypes.IndexingRewards, otherAllocationData])
        expect(otherRewards).to.not.equal(0n, 'Rewards should be greater than zero')

        // Verify total rewards collected
        const afterFirstCollectionProvisionTokens = (await staking.getProvision(indexer.address, subgraphService.target)).tokens
        expect(afterFirstCollectionProvisionTokens).to.equal(beforeProvisionTokens + rewards + otherRewards, 'Rewards should be collected continuously')

        // Mine multiple blocks to simulate time passing
        for (let i = 0; i < 500; i++) {
          await ethers.provider.send('evm_mine', [])
        }

        // Collect rewards for first allocation
        rewards = await collect(indexer, [indexer.address, PaymentTypes.IndexingRewards, allocationData])
        expect(rewards).to.not.equal(0n, 'Rewards should be greater than zero')

        // Collect rewards for second allocation
        otherRewards = await collect(indexer, [indexer.address, PaymentTypes.IndexingRewards, otherAllocationData])
        expect(otherRewards).to.not.equal(0n, 'Rewards should be greater than zero')

        // Verify total rewards collected
        const afterSecondCollectionProvisionTokens = (await staking.getProvision(indexer.address, subgraphService.target)).tokens
        expect(afterSecondCollectionProvisionTokens).to.equal(afterFirstCollectionProvisionTokens + rewards + otherRewards, 'Rewards should be collected continuously')
      })

      it('should not collect rewards after POI staleness', async () => {
        // Get before provision tokens
        const beforeProvisionTokens = (await staking.getProvision(indexer.address, subgraphService.target)).tokens

        // Wait for POI staleness
        const maxPOIStaleness = await subgraphService.maxPOIStaleness()
        await ethers.provider.send('evm_increaseTime', [Number(maxPOIStaleness) + 1])
        await ethers.provider.send('evm_mine', [])

        // Build data for collect indexing rewards
        const poi = generatePOI()
        const data = encodeCollectData(allocationId, poi)

        // Attempt to collect rewards
        await subgraphService.connect(indexer).collect(
          indexer.address,
          PaymentTypes.IndexingRewards,
          data,
        )

        // Verify no rewards were collected
        const afterProvisionTokens = (await staking.getProvision(indexer.address, subgraphService.target)).tokens
        expect(afterProvisionTokens).to.equal(beforeProvisionTokens, 'Rewards should not be collected after POI staleness')
      })

      describe('Over allocated', () => {
        let subgraphDeploymentId: string
        let delegator: HardhatEthersSigner
        let allocationPrivateKey: string
        beforeEach(async () => {
          // Get delegator
          delegator = await ethers.getSigner(delegators[0].address)

          // Get locked tokens
          const lockedTokens = await subgraphService.allocationProvisionTracker(indexer.address)

          // Get delegation ratio
          const delegationRatio = await subgraphService.getDelegationRatio()
          const availableTokens = await staking.getTokensAvailable(indexer.address, subgraphService.target, delegationRatio)

          // Create allocation with tokens available
          const wallet = ethers.Wallet.createRandom()
          allocationId = wallet.address
          allocationPrivateKey = wallet.privateKey
          subgraphDeploymentId = indexers[0].allocations[0].subgraphDeploymentID
          const allocationTokens = availableTokens - lockedTokens
          const signature = await generateAllocationProof(indexer.address, allocationPrivateKey, subgraphServiceAddress, chainId)
          const data = encodeStartServiceData(subgraphDeploymentId, allocationTokens, allocationId, signature)
          await subgraphService.connect(indexer).startService(
            indexer.address,
            data,
          )

          // Undelegate from indexer so they become over allocated
          const delegation = await staking.getDelegation(
            indexer.address,
            subgraphService.target,
            delegator.address,
          )

          // Undelegate tokens
          await staking.connect(delegator)['undelegate(address,address,uint256)'](indexer.address, subgraphServiceAddress, delegation.shares)
        })

        it('should collect rewards while over allocated with fresh POI', async () => {
          // Get before provision tokens
          const beforeProvisionTokens = (await staking.getProvision(indexer.address, subgraphService.target)).tokens

          // Mine multiple blocks to simulate time passing
          for (let i = 0; i < 1000; i++) {
            await ethers.provider.send('evm_mine', [])
          }

          // Build data for collect indexing rewards
          const poi = generatePOI()
          const data = encodeCollectData(allocationId, poi)

          // Collect rewards
          const rewards = await collect(indexer, [indexer.address, PaymentTypes.IndexingRewards, data])
          expect(rewards).to.not.equal(0n, 'Rewards should be greater than zero')

          // Verify rewards are added to provision
          const afterProvisionTokens = (await staking.getProvision(indexer.address, subgraphService.target)).tokens
          expect(afterProvisionTokens).to.equal(beforeProvisionTokens + rewards, 'Rewards should be collected')

          // Verify allocation was closed
          const allocation = await subgraphService.getAllocation(allocationId)
          expect(allocation.closedAt).to.not.equal(0)
        })
      })
    })

    describe('With rewards destination', () => {
      let rewardsDestination: string

      beforeEach(async () => {
        // Get indexer
        const indexerFixture = indexers[1]
        indexer = await ethers.getSigner(indexerFixture.address)

        // Get allocation
        const allocation = indexerFixture.allocations[0]
        allocationId = allocation.allocationID

        // Check rewards destination is set
        rewardsDestination = await subgraphService.rewardsDestination(indexer.address)
        expect(rewardsDestination).not.equal(ethers.ZeroAddress, 'Rewards destination should be set')
      })

      it('should collect indexing rewards with rewards destination', async () => {
        // Get before balance of rewards destination
        const beforeRewardsDestinationBalance = await graphToken.balanceOf(rewardsDestination)

        // Mine multiple blocks to simulate time passing
        for (let i = 0; i < 500; i++) {
          await ethers.provider.send('evm_mine', [])
        }

        // Build data for collect indexing rewards
        const poi = generatePOI()
        const data = encodeCollectData(allocationId, poi)

        // Collect rewards
        const rewards = await collect(indexer, [indexer.address, PaymentTypes.IndexingRewards, data])
        expect(rewards).to.not.equal(0n, 'Rewards should be greater than zero')

        // Verify rewards are transferred to rewards destination
        const afterRewardsDestinationBalance = await graphToken.balanceOf(rewardsDestination)
        expect(afterRewardsDestinationBalance).to.equal(beforeRewardsDestinationBalance + rewards, 'Rewards should be transferred to rewards destination')
      })
    })
  })

  describe('Query Fees', () => {
    let payer: HDNodeWallet
    let signer: HDNodeWallet
    let allocationId: string
    let otherAllocationId: string
    let collectTokens: bigint

    before(async () => {
      // Get payer
      payer = ethers.Wallet.createRandom()
      payer = payer.connect(ethers.provider)

      // Get signer
      signer = ethers.Wallet.createRandom()

      // Mint GRT to payer and fund payer and signer with ETH
      await setGRTBalance(graph.provider, graphToken.target, payer.address, ethers.parseEther('1000000'))
      await ethers.provider.send('hardhat_setBalance', [payer.address, '0x56BC75E2D63100000'])
      await ethers.provider.send('hardhat_setBalance', [signer.address, '0x56BC75E2D63100000'])

      // Authorize payer as signer
      // Block timestamp plus 1 year
      const proofDeadline = (await ethers.provider.getBlock('latest'))!.timestamp + 31536000
      const signerProof = await getSignerProof(BigInt(proofDeadline), payer.address, signer.privateKey, graphTallyCollectorAddress, chainId)
      await graphTallyCollector.connect(payer).authorizeSigner(signer.address, proofDeadline, signerProof)

      // Get indexer
      const indexerFixture = indexers[0]
      indexer = await ethers.getSigner(indexerFixture.address)

      // Get allocation
      allocationId = indexerFixture.allocations[0].allocationID
      otherAllocationId = indexerFixture.allocations[1].allocationID
      // Get collect tokens
      collectTokens = ethers.parseUnits('1000')
    })

    beforeEach(async () => {
      // Deposit tokens in escrow
      await graphToken.connect(payer).approve(escrow.target, collectTokens)
      await escrow.connect(payer).deposit(graphTallyCollector.target, indexer.address, collectTokens)
    })

    it('should collect query fees with SignedRAV', async () => {
      const encodedSignedRAV = await getSignedRAVCalldata(
        allocationId,
        payer.address,
        indexer.address,
        subgraphServiceAddress,
        0,
        collectTokens,
        ethers.toUtf8Bytes(''),
        signer.privateKey,
        graphTallyCollectorAddress,
        chainId,
      )

      // Get balance before collect
      const beforeBalance = await graphToken.balanceOf(indexer.address)

      // Collect query fees
      await collect(indexer, [indexer.address, PaymentTypes.QueryFee, encodedSignedRAV])

      // Calculate expected rewards
      const rewardsAfterTax = collectTokens - (collectTokens * BigInt(await graphPayments.PROTOCOL_PAYMENT_CUT())) / BigInt(1e6)
      const rewardsAfterCuration = rewardsAfterTax - (rewardsAfterTax * BigInt(await subgraphService.curationFeesCut())) / BigInt(1e6)

      // Verify indexer received tokens
      const afterBalance = await graphToken.balanceOf(indexer.address)
      expect(afterBalance).to.equal(beforeBalance + rewardsAfterCuration)
    })

    it('should collect multiple SignedRAVs', async () => {
      // Get before balance
      const beforeBalance = await graphToken.balanceOf(indexer.address)

      // Get fees
      const fees1 = collectTokens / 4n
      const fees2 = collectTokens / 2n

      // Get encoded SignedRAVs
      const encodedSignedRAV1 = await getSignedRAVCalldata(
        allocationId,
        payer.address,
        indexer.address,
        subgraphServiceAddress,
        0,
        fees1,
        ethers.toUtf8Bytes(''),
        signer.privateKey,
        graphTallyCollectorAddress,
        chainId,
      )
      const encodedSignedRAV2 = await getSignedRAVCalldata(
        otherAllocationId,
        payer.address,
        indexer.address,
        subgraphServiceAddress,
        0,
        fees2,
        ethers.toUtf8Bytes(''),
        signer.privateKey,
        graphTallyCollectorAddress,
        chainId,
      )

      // Collect first set of fees
      const rewards1 = await collect(indexer, [indexer.address, PaymentTypes.QueryFee, encodedSignedRAV1])

      // Collect second set of fees
      const rewards2 = await collect(indexer, [indexer.address, PaymentTypes.QueryFee, encodedSignedRAV2])

      // Verify total rewards collected
      const totalRewards = rewards1 + rewards2
      const totalRewardsAfterTax = totalRewards - (totalRewards * BigInt(await graphPayments.PROTOCOL_PAYMENT_CUT())) / BigInt(1e6)
      const totalRewardsAfterCuration = totalRewardsAfterTax - (totalRewardsAfterTax * BigInt(await subgraphService.curationFeesCut())) / BigInt(1e6)

      // Verify indexer received tokens
      const afterBalance = await graphToken.balanceOf(indexer.address)
      expect(afterBalance).to.equal(beforeBalance + totalRewardsAfterCuration)

      // Collect new RAV for allocation 1
      const newFees1 = fees1 * 2n
      const newRAV1 = await getSignedRAVCalldata(
        allocationId,
        payer.address,
        indexer.address,
        subgraphServiceAddress,
        0,
        newFees1,
        ethers.toUtf8Bytes(''),
        signer.privateKey,
        graphTallyCollectorAddress,
        chainId,
      )

      // Collect new RAV for allocation 1
      const newRewards1 = await collect(indexer, [indexer.address, PaymentTypes.QueryFee, newRAV1])

      // Verify only the difference was collected
      expect(newRewards1).to.equal(newFees1 - fees1)
    })
  })
})
