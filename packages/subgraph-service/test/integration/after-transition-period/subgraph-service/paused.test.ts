import { ethers } from 'hardhat'
import { expect } from 'chai'
import hre from 'hardhat'

import { DisputeManager, IGraphToken, SubgraphService } from '../../../../typechain-types'
import { setGRTBalance } from '@graphprotocol/toolshed/hardhat'
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

import { encodeCollectData, encodeRegistrationData, encodeStartServiceData, generateAllocationProof, generatePOI, PaymentTypes } from '@graphprotocol/toolshed'
import { indexers } from '../../../../tasks/test/fixtures/indexers'

describe('Paused Protocol', () => {
  let disputeManager: DisputeManager
  let graphToken: IGraphToken
  let subgraphService: SubgraphService

  let snapshotId: string
  let chainId: number

  // Test addresses
  let pauseGuardian: HardhatEthersSigner
  let indexer: HardhatEthersSigner
  let allocationId: string
  let subgraphDeploymentId: string
  let allocationTokens: bigint
  let subgraphServiceAddress: string

  const graph = hre.graph()
  const { provision } = graph.horizon.actions
  const { collect } = graph.subgraphService.actions

  before(async () => {
    // Get contracts
    disputeManager = graph.subgraphService.contracts.DisputeManager
    graphToken = graph.horizon.contracts.GraphToken
    subgraphService = graph.subgraphService.contracts.SubgraphService

    // Get signers
    pauseGuardian = await graph.accounts.getPauseGuardian()

    // Get chain id
    chainId = Number((await hre.ethers.provider.getNetwork()).chainId)

    // Get subgraph service address
    subgraphServiceAddress = await subgraphService.getAddress()
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])

    // Get indexer
    ;[indexer] = await graph.accounts.getTestAccounts()
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
          const poi = generatePOI()
          const data = encodeCollectData(allocationId, poi)

          await expect(
            collect(indexer, [indexer.address, PaymentTypes.IndexingRewards, data]),
          ).to.be.revertedWithCustomError(
            subgraphService,
            'EnforcedPause',
          )
        })

        it('should not allow indexer to collect query fees while paused', async () => {
          // Build data for collect query fees
          const poi = generatePOI()
          const data = encodeCollectData(allocationId, poi)

          await expect(
            collect(indexer, [indexer.address, PaymentTypes.QueryFee, data]),
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
        let allocationPrivateKey: string

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
          const signature = await generateAllocationProof(indexer.address, allocationPrivateKey, subgraphServiceAddress, chainId)

          // Build allocation data
          const data = encodeStartServiceData(subgraphDeploymentId, allocationTokens, allocationId, signature)

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
        [indexer] = await graph.accounts.getTestAccounts()

        // Create provision
        const disputePeriod = await disputeManager.getDisputePeriod()
        const maxSlashingCut = await disputeManager.maxSlashingCut()
        await setGRTBalance(graph.provider, graphToken.target, indexer.address, ethers.parseEther('100000'))
        await provision(indexer, [indexer.address, await subgraphService.getAddress(), ethers.parseEther('100000'), maxSlashingCut, disputePeriod])
      })

      it('should not allow indexer to register while paused', async () => {
        const indexerUrl = 'https://test-indexer.com'
        const indexerGeoHash = 'test-geo-hash'
        const indexerRegistrationData = encodeRegistrationData(indexerUrl, indexerGeoHash, ethers.ZeroAddress)

        await expect(
          subgraphService.connect(indexer).register(indexer.address, indexerRegistrationData),
        ).to.be.revertedWithCustomError(
          subgraphService,
          'EnforcedPause',
        )
      })
    })

    describe('Permissionless', () => {
      let anyone: HardhatEthersSigner

      before(async () => {
        // Get anyone address
        [anyone] = await graph.accounts.getTestAccounts()
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
