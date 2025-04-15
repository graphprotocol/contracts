import { ethers } from 'hardhat'
import { expect } from 'chai'
import { HDNodeWallet } from 'ethers'
import hre from 'hardhat'

import { DisputeManager, IGraphToken, IHorizonStaking, IPaymentsEscrow, SubgraphService } from '../../../../typechain-types'
import { getSignedRAVCalldata, getSignerProof } from '@graphprotocol/toolshed'
import { GraphTallyCollector } from '@graphprotocol/horizon'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

import { indexers } from '../../../../tasks/test/fixtures/indexers'
import { PaymentTypes } from '@graphprotocol/toolshed'
import { setGRTBalance } from '@graphprotocol/toolshed/hardhat'

describe('Operator', () => {
  let subgraphService: SubgraphService
  let staking: IHorizonStaking
  let graphToken: IGraphToken
  let escrow: IPaymentsEscrow
  let disputeManager: DisputeManager
  let graphTallyCollector: GraphTallyCollector

  let snapshotId: string

  // Test addresses
  let indexer: SignerWithAddress
  let authorizedOperator: HDNodeWallet
  let unauthorizedOperator: HDNodeWallet
  let allocationId: string
  let subgraphDeploymentId: string
  let allocationTokens: bigint

  const graph = hre.graph()
  const { provision } = graph.horizon.actions
  const { collect, generateAllocationProof } = graph.subgraphService.actions

  before(async () => {
    // Get contracts
    subgraphService = graph.subgraphService.contracts.SubgraphService as unknown as SubgraphService
    staking = graph.horizon.contracts.HorizonStaking as unknown as IHorizonStaking
    graphToken = graph.horizon.contracts.GraphToken as unknown as IGraphToken
    escrow = graph.horizon.contracts.PaymentsEscrow as unknown as IPaymentsEscrow
    graphTallyCollector = graph.horizon.contracts.GraphTallyCollector as unknown as GraphTallyCollector
    disputeManager = graph.subgraphService.contracts.DisputeManager as unknown as DisputeManager

    // Get signers
    authorizedOperator = ethers.Wallet.createRandom()
    authorizedOperator = authorizedOperator.connect(ethers.provider)
    unauthorizedOperator = ethers.Wallet.createRandom()
    unauthorizedOperator = unauthorizedOperator.connect(ethers.provider)

    // Set balances for authorized operator
    await ethers.provider.send('hardhat_setBalance', [authorizedOperator.address, '0x56BC75E2D63100000'])
    await ethers.provider.send('hardhat_setBalance', [unauthorizedOperator.address, '0x56BC75E2D63100000'])
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe('New indexer', () => {
    beforeEach(async () => {
      // Get indexer
      const signers = await ethers.getSigners()
      indexer = await ethers.getSigner(signers[19].address)

      // Create provision
      const disputePeriod = await disputeManager.getDisputePeriod()
      const maxSlashingCut = await disputeManager.maxSlashingCut()
      await setGRTBalance(graph.provider, graphToken.target, indexer.address, ethers.parseEther('100000'))
      await provision(indexer, [indexer.address, await subgraphService.getAddress(), ethers.parseEther('100000'), maxSlashingCut, disputePeriod])
    })

    describe('Authorized Operator', () => {
      beforeEach(async () => {
        // Authorize operator
        await staking.connect(indexer).setOperator(await subgraphService.getAddress(), authorizedOperator.address, true)
      })

      it('should be able to register the indexer', async () => {
        const indexerUrl = 'https://test-indexer.com'
        const indexerGeoHash = 'test-geo-hash'
        const indexerRegistrationData = hre.ethers.AbiCoder.defaultAbiCoder().encode(
          ['string', 'string', 'address'],
          [indexerUrl, indexerGeoHash, ethers.ZeroAddress],
        )

        await subgraphService.connect(authorizedOperator).register(indexer.address, indexerRegistrationData)

        // Verify indexer metadata
        const indexerInfo = await subgraphService.indexers(indexer.address)
        expect(indexerInfo.url).to.equal(indexerUrl)
        expect(indexerInfo.geoHash).to.equal(indexerGeoHash)
      })
    })

    describe('Unauthorized Operator', () => {
      it('should not be able to register the indexer', async () => {
        const indexerUrl = 'https://test-indexer.com'
        const indexerGeoHash = 'test-geo-hash'
        const indexerRegistrationData = hre.ethers.AbiCoder.defaultAbiCoder().encode(
          ['string', 'string', 'address'],
          [indexerUrl, indexerGeoHash, ethers.ZeroAddress],
        )

        await expect(
          subgraphService.connect(unauthorizedOperator).register(indexer.address, indexerRegistrationData),
        ).to.be.revertedWithCustomError(
          subgraphService,
          'ProvisionManagerNotAuthorized',
        )
      })
    })
  })

  describe('Existing indexer', () => {
    beforeEach(async () => {
      // Get indexer
      const indexerFixture = indexers[0]
      indexer = await ethers.getSigner(indexerFixture.address)
    })

    describe('New allocation', () => {
      let allocationPrivateKey: string

      beforeEach(() => {
        // Generate test allocation
        const wallet = ethers.Wallet.createRandom()
        allocationId = wallet.address
        allocationPrivateKey = wallet.privateKey
        subgraphDeploymentId = ethers.keccak256(ethers.toUtf8Bytes('test-subgraph-deployment'))
        allocationTokens = ethers.parseEther('10000')
      })

      describe('Authorized Operator', () => {
        beforeEach(async () => {
          // Authorize operator
          await staking.connect(indexer).setOperator(await subgraphService.getAddress(), authorizedOperator.address, true)
        })

        it('should be able to create an allocation', async () => {
          // Build allocation proof
          const signature = await generateAllocationProof(allocationPrivateKey, [indexer.address, allocationId])

          // Build allocation data
          const data = ethers.AbiCoder.defaultAbiCoder().encode(
            ['bytes32', 'uint256', 'address', 'bytes'],
            [subgraphDeploymentId, allocationTokens, allocationId, signature],
          )

          // Start allocation
          await subgraphService.connect(authorizedOperator).startService(
            indexer.address,
            data,
          )

          // Verify allocation
          const allocation = await subgraphService.getAllocation(allocationId)
          expect(allocation.indexer).to.equal(indexer.address)
          expect(allocation.tokens).to.equal(allocationTokens)
          expect(allocation.subgraphDeploymentId).to.equal(subgraphDeploymentId)
        })
      })

      describe('Unauthorized Operator', () => {
        it('should not be able to create an allocation', async () => {
          // Build allocation proof
          const signature = await generateAllocationProof(allocationPrivateKey, [indexer.address, allocationId])

          // Build allocation data
          const data = ethers.AbiCoder.defaultAbiCoder().encode(
            ['bytes32', 'uint256', 'address', 'bytes'],
            [subgraphDeploymentId, allocationTokens, allocationId, signature],
          )

          await expect(
            subgraphService.connect(unauthorizedOperator).startService(
              indexer.address,
              data,
            ),
          ).to.be.revertedWithCustomError(
            subgraphService,
            'ProvisionManagerNotAuthorized',
          )
        })
      })
    })

    describe('Open allocation', () => {
      beforeEach(() => {
        // Get allocation data
        const allocationFixture = indexers[0].allocations[0]
        allocationId = allocationFixture.allocationID
        subgraphDeploymentId = allocationFixture.subgraphDeploymentID
        allocationTokens = allocationFixture.tokens
      })

      describe('Authorized Operator', () => {
        beforeEach(async () => {
          // Authorize operator
          await staking.connect(indexer).setOperator(await subgraphService.getAddress(), authorizedOperator.address, true)
        })

        it('should be able to resize an allocation', async () => {
          // Resize allocation
          const newAllocationTokens = allocationTokens + ethers.parseEther('5000')
          await subgraphService.connect(authorizedOperator).resizeAllocation(
            indexer.address,
            allocationId,
            newAllocationTokens,
          )

          // Verify allocation
          const allocation = await subgraphService.getAllocation(allocationId)
          expect(allocation.tokens).to.equal(newAllocationTokens)
        })

        it('should be able to close an allocation', async () => {
          // Close allocation
          const data = ethers.AbiCoder.defaultAbiCoder().encode(
            ['address'],
            [allocationId],
          )
          await subgraphService.connect(authorizedOperator).stopService(
            indexer.address,
            data,
          )

          // Verify allocation is closed
          const allocation = await subgraphService.getAllocation(allocationId)
          expect(allocation.closedAt).to.not.equal(0)
        })

        it('should be able to collect indexing rewards', async () => {
          // Mine multiple blocks to simulate time passing
          for (let i = 0; i < 1000; i++) {
            await ethers.provider.send('evm_mine', [])
          }

          // Build data for collect indexing rewards
          const poi = ethers.keccak256(ethers.toUtf8Bytes('test-poi'))
          const collectData = ethers.AbiCoder.defaultAbiCoder().encode(
            ['address', 'bytes32'],
            [allocationId, poi],
          )

          // Collect rewards
          const rewards = await collect(authorizedOperator, [indexer.address, PaymentTypes.IndexingRewards, collectData])
          expect(rewards).to.not.equal(0n)
        })

        it('should be able to collect query fees', async () => {
          // Setup query fees collection
          let payer = ethers.Wallet.createRandom()
          payer = payer.connect(ethers.provider)
          let signer = ethers.Wallet.createRandom()
          signer = signer.connect(ethers.provider)
          const collectTokens = ethers.parseUnits('1000')

          // Mint GRT to payer and fund payer and signer with ETH
          await setGRTBalance(graph.provider, graphToken.target, payer.address, ethers.parseEther('1000000'))
          await ethers.provider.send('hardhat_setBalance', [payer.address, '0x56BC75E2D63100000'])
          await ethers.provider.send('hardhat_setBalance', [signer.address, '0x56BC75E2D63100000'])

          // Authorize payer as signer
          const chainId = (await ethers.provider.getNetwork()).chainId
          const proofDeadline = (await ethers.provider.getBlock('latest'))!.timestamp + 31536000
          const signerProof = await getSignerProof(graphTallyCollector, signer, chainId, BigInt(proofDeadline), payer.address)
          await graphTallyCollector.connect(payer).authorizeSigner(signer.address, proofDeadline, signerProof)

          // Deposit tokens in escrow
          await graphToken.connect(payer).approve(escrow.target, collectTokens)
          await escrow.connect(payer).deposit(graphTallyCollector.target, indexer.address, collectTokens)

          // Get encoded SignedRAV
          const encodedSignedRAV = await getSignedRAVCalldata(
            graphTallyCollector,
            signer,
            allocationId,
            payer.address,
            indexer.address,
            await subgraphService.getAddress(),
            0,
            collectTokens,
            ethers.toUtf8Bytes(''),
          )

          // Collect query fees
          const rewards = await collect(authorizedOperator, [indexer.address, PaymentTypes.QueryFee, encodedSignedRAV])
          expect(rewards).to.not.equal(0n)
        })
      })

      describe('Unauthorized Operator', () => {
        it('should not be able to resize an allocation', async () => {
          // Attempt to resize with unauthorized operator
          const newAllocationTokens = allocationTokens + ethers.parseEther('5000')
          await expect(
            subgraphService.connect(unauthorizedOperator).resizeAllocation(
              indexer.address,
              allocationId,
              newAllocationTokens,
            ),
          ).to.be.revertedWithCustomError(
            subgraphService,
            'ProvisionManagerNotAuthorized',
          )
        })

        it('should not be able to close an allocation', async () => {
          // Attempt to close with unauthorized operator
          await expect(
            subgraphService.connect(unauthorizedOperator).stopService(
              indexer.address,
              allocationId,
            ),
          ).to.be.revertedWithCustomError(
            subgraphService,
            'ProvisionManagerNotAuthorized',
          )
        })

        it('should not be able to collect indexing rewards', async () => {
          // Mine multiple blocks to simulate time passing
          for (let i = 0; i < 1000; i++) {
            await ethers.provider.send('evm_mine', [])
          }

          // Build data for collect indexing rewards
          const poi = ethers.keccak256(ethers.toUtf8Bytes('test-poi'))
          const collectData = ethers.AbiCoder.defaultAbiCoder().encode(
            ['address', 'bytes32'],
            [allocationId, poi],
          )

          // Attempt to collect rewards with unauthorized operator
          await expect(
            collect(unauthorizedOperator, [indexer.address, PaymentTypes.IndexingRewards, collectData]),
          ).to.be.revertedWithCustomError(
            subgraphService,
            'ProvisionManagerNotAuthorized',
          )
        })

        it('should not be able to collect query fees', async () => {
          // Setup query fees collection
          let payer = ethers.Wallet.createRandom()
          payer = payer.connect(ethers.provider)
          let signer = ethers.Wallet.createRandom()
          signer = signer.connect(ethers.provider)
          const collectTokens = ethers.parseUnits('1000')

          // Mint GRT to payer and fund payer and signer with ETH
          await setGRTBalance(graph.provider, graphToken.target, payer.address, ethers.parseEther('1000000'))
          await ethers.provider.send('hardhat_setBalance', [payer.address, '0x56BC75E2D63100000'])
          await ethers.provider.send('hardhat_setBalance', [signer.address, '0x56BC75E2D63100000'])

          // Authorize payer as signer
          const chainId = (await ethers.provider.getNetwork()).chainId
          const proofDeadline = (await ethers.provider.getBlock('latest'))!.timestamp + 31536000
          const signerProof = await getSignerProof(graphTallyCollector, signer, chainId, BigInt(proofDeadline), payer.address)
          await graphTallyCollector.connect(payer).authorizeSigner(signer.address, proofDeadline, signerProof)

          // Deposit tokens in escrow
          await graphToken.connect(payer).approve(escrow.target, collectTokens)
          await escrow.connect(payer).deposit(escrow.target, indexer.address, collectTokens)

          // Get encoded SignedRAV
          const encodedSignedRAV = await getSignedRAVCalldata(
            graphTallyCollector,
            signer,
            allocationId,
            payer.address,
            indexer.address,
            await subgraphService.getAddress(),
            0,
            collectTokens,
            ethers.toUtf8Bytes(''),
          )

          // Attempt to collect query fees with unauthorized operator
          await expect(
            collect(unauthorizedOperator, [indexer.address, PaymentTypes.QueryFee, encodedSignedRAV]),
          ).to.be.revertedWithCustomError(
            subgraphService,
            'ProvisionManagerNotAuthorized',
          )
        })
      })
    })
  })
})
