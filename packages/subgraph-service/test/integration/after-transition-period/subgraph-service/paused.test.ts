import { ethers } from 'hardhat'
import { expect } from 'chai'
import hre from 'hardhat'

import { DisputeManager, IGraphToken, IHorizonStaking, SubgraphService } from '../../../../typechain-types'
import { generateAllocationProof, HorizonStakingActions, HorizonTypes, SubgraphServiceActions } from 'hardhat-graph-protocol/sdk'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

import { indexers } from '../../../../tasks/test/fixtures/indexers'

describe('Paused Protocol', () => {
  let disputeManager: DisputeManager
  let graphToken: IGraphToken
  let staking: IHorizonStaking
  let subgraphService: SubgraphService

  let snapshotId: string

  // Test addresses
  let pauseGuardian: SignerWithAddress
  let indexer: SignerWithAddress
  let allocationId: string
  let allocationPrivateKey: string
  let subgraphDeploymentId: string
  let allocationTokens: bigint

  before(async () => {
    // Get contracts
    const graph = hre.graph()
    disputeManager = graph.subgraphService!.contracts.DisputeManager as unknown as DisputeManager
    graphToken = graph.horizon!.contracts.GraphToken as unknown as IGraphToken
    staking = graph.horizon!.contracts.HorizonStaking as unknown as IHorizonStaking
    subgraphService = graph.subgraphService!.contracts.SubgraphService as unknown as SubgraphService

    // Get signers
    const signers = await ethers.getSigners()
    pauseGuardian = signers[3]
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])

    // Get indexer
    const signers = await ethers.getSigners()
    indexer = signers[18]

    // Get allocation
    const wallet = ethers.Wallet.createRandom()
    allocationId = wallet.address
    allocationPrivateKey = wallet.privateKey
    subgraphDeploymentId = indexers[0].allocations[0].subgraphDeploymentID
    allocationTokens = 1000n
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe('Pause actions', () => {
    it('should allow pause guardian to pause the protocol', async () => {
      await subgraphService.connect(pauseGuardian).pause()
      expect(await subgraphService.paused()).to.be.true
    })

    it('should allow pause guardian to unpause the protocol', async () => {
      // First pause the protocol
      await subgraphService.connect(pauseGuardian).pause()
      expect(await subgraphService.paused()).to.be.true

      // Then unpause it
      await subgraphService.connect(pauseGuardian).unpause()
      expect(await subgraphService.paused()).to.be.false
    })
  })

  describe('Indexer Operations While Paused', () => {
    beforeEach(async () => {
      // Pause the protocol before each test
      await subgraphService.connect(pauseGuardian).pause()
    })

    describe('Existing indexer', () => {
      beforeEach(async () => {
        // Get indexer
        const indexerFixture = indexers[0]
        indexer = await ethers.getSigner(indexerFixture.address)
      })

      describe('Opened allocation', () => {
        beforeEach(() => {
          // Get allocation
          const allocation = indexers[0].allocations[0]
          allocationId = allocation.allocationID
          allocationPrivateKey = allocation.allocationPrivateKey
          subgraphDeploymentId = allocation.subgraphDeploymentID
          allocationTokens = allocation.tokens
        })

        it('should not allow indexer to stop an allocation while paused', async () => {
          await expect(
            subgraphService.connect(indexer).stopService(
              indexer.address,
              allocationId,
            ),
          ).to.be.revertedWithCustomError(
            subgraphService,
            'EnforcedPause',
          )
        })

        it('should not allow indexer to collect indexing rewards while paused', async () => {
          // Build data for collect indexing rewards
          const poi = ethers.keccak256(ethers.toUtf8Bytes('test-poi'))
          const data = ethers.AbiCoder.defaultAbiCoder().encode(
            ['address', 'bytes32'],
            [allocationId, poi],
          )

          await expect(
            SubgraphServiceActions.collect({
              subgraphService,
              signer: indexer,
              indexer: indexer.address,
              paymentType: HorizonTypes.PaymentTypes.IndexingRewards,
              data,
            }),
          ).to.be.revertedWithCustomError(
            subgraphService,
            'EnforcedPause',
          )
        })

        it('should not allow indexer to collect query fees while paused', async () => {
          // Build data for collect query fees
          const poi = ethers.keccak256(ethers.toUtf8Bytes('test-poi'))
          const data = ethers.AbiCoder.defaultAbiCoder().encode(
            ['address', 'bytes32'],
            [allocationId, poi],
          )

          await expect(
            SubgraphServiceActions.collect({
              subgraphService,
              signer: indexer,
              indexer: indexer.address,
              paymentType: HorizonTypes.PaymentTypes.QueryFee,
              data,
            }),
          ).to.be.revertedWithCustomError(
            subgraphService,
            'EnforcedPause',
          )
        })

        it('should not allow indexer to resize an allocation while paused', async () => {
          await expect(
            subgraphService.connect(indexer).resizeAllocation(
              indexer.address,
              allocationId,
              allocationTokens + ethers.parseEther('1000'),
            ),
          ).to.be.revertedWithCustomError(
            subgraphService,
            'EnforcedPause',
          )
        })
      })

      describe('New allocation', () => {
        beforeEach(() => {
          // Get allocation
          const wallet = ethers.Wallet.createRandom()
          allocationId = wallet.address
          allocationPrivateKey = wallet.privateKey
          subgraphDeploymentId = indexers[0].allocations[0].subgraphDeploymentID
          allocationTokens = 1000n
        })

        it('should not allow indexer to start an allocation while paused', async () => {
          // Build allocation proof
          const signature = await generateAllocationProof(subgraphService, indexer.address, allocationPrivateKey)

          // Build allocation data
          const data = ethers.AbiCoder.defaultAbiCoder().encode(
            ['bytes32', 'uint256', 'address', 'bytes'],
            [subgraphDeploymentId, allocationTokens, allocationId, signature],
          )

          await expect(
            subgraphService.connect(indexer).startService(
              indexer.address,
              data,
            ),
          ).to.be.revertedWithCustomError(
            subgraphService,
            'EnforcedPause',
          )
        })
      })
    })

    describe('New indexer', () => {
      beforeEach(async () => {
        // Get indexer
        const signers = await ethers.getSigners()
        indexer = await ethers.getSigner(signers[19].address)

        // Add stake
        await HorizonStakingActions.stake({
          horizonStaking: staking,
          graphToken,
          serviceProvider: indexer,
          tokens: ethers.parseEther('100000'),
        })

        // Create provision
        const disputePeriod = await disputeManager.getDisputePeriod()
        const maxSlashingCut = await disputeManager.maxSlashingCut()
        await HorizonStakingActions.createProvision({
          horizonStaking: staking,
          serviceProvider: indexer,
          tokens: ethers.parseEther('100000'),
          maxVerifierCut: maxSlashingCut,
          thawingPeriod: disputePeriod,
          verifier: await subgraphService.getAddress(),
        })
      })

      it('should not allow indexer to register while paused', async () => {
        const indexerUrl = 'https://test-indexer.com'
        const indexerGeoHash = 'test-geo-hash'
        const indexerRegistrationData = hre.ethers.AbiCoder.defaultAbiCoder().encode(
          ['string', 'string', 'address'],
          [indexerUrl, indexerGeoHash, ethers.ZeroAddress],
        )

        await expect(
          subgraphService.connect(indexer).register(indexer.address, indexerRegistrationData),
        ).to.be.revertedWithCustomError(
          subgraphService,
          'EnforcedPause',
        )
      })
    })

    describe('Permissionless', () => {
      let anyone: SignerWithAddress

      before(async () => {
        // Get anyone address
        const signers = await ethers.getSigners()
        anyone = signers[3]
      })

      it('should not allow anyone to close a stale allocation while paused', async () => {
        // Wait for POI staleness
        const maxPOIStaleness = await subgraphService.maxPOIStaleness()
        await ethers.provider.send('evm_increaseTime', [Number(maxPOIStaleness) + 1])
        await ethers.provider.send('evm_mine', [])

        await expect(
          subgraphService.connect(anyone).closeStaleAllocation(allocationId),
        ).to.be.revertedWithCustomError(
          subgraphService,
          'EnforcedPause',
        )
      })
    })
  })
})
