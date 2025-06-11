import { HorizonStaking } from '@graphprotocol/horizon'
import {
  generateAttestationData,
  generateLegacyIndexingDisputeId,
  generateLegacyQueryDisputeId,
} from '@graphprotocol/toolshed'
import type { LegacyDisputeManager } from '@graphprotocol/toolshed/deployments'
import { setGRTBalance } from '@graphprotocol/toolshed/hardhat'
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'
import { expect } from 'chai'
import { ethers } from 'hardhat'
import hre from 'hardhat'

import { indexers } from '../../../tasks/test/fixtures/indexers'
import { IGraphToken } from '../../../typechain-types'

describe('Legacy Dispute Manager', () => {
  let legacyDisputeManager: LegacyDisputeManager
  let graphToken: IGraphToken
  let staking: HorizonStaking

  let snapshotId: string

  let governor: HardhatEthersSigner
  let arbitrator: HardhatEthersSigner
  let indexer: HardhatEthersSigner
  let fisherman: HardhatEthersSigner

  let disputeDeposit: bigint

  const graph = hre.graph()

  // We have to use Aribtrm Sepolia since we're testing an already deployed contract but running on a hardhat fork
  const chainId = 421614

  before(async () => {
    governor = await graph.accounts.getGovernor()
    ;[arbitrator, fisherman] = await graph.accounts.getTestAccounts()

    // Get contract instances with correct types
    legacyDisputeManager = graph.subgraphService.contracts.LegacyDisputeManager
    graphToken = graph.horizon.contracts.GraphToken
    staking = graph.horizon.contracts.HorizonStaking

    // Set GRT balances
    await setGRTBalance(graph.provider, graphToken.target, fisherman.address, ethers.parseEther('100000'))
  })

  beforeEach(async () => {
    // Take a snapshot before each test
    snapshotId = await ethers.provider.send('evm_snapshot', [])

    // Legacy dispute manager
    disputeDeposit = ethers.parseEther('10000')

    // Set arbitrator
    await legacyDisputeManager.connect(governor).setArbitrator(arbitrator.address)
  })

  afterEach(async () => {
    // Revert to the snapshot after each test
    await ethers.provider.send('evm_revert', [snapshotId])
  })

  describe('Indexing Disputes', () => {
    let allocationId: string

    beforeEach(async () => {
      // Get Indexer
      const indexerFixture = indexers[0]
      indexer = await ethers.getSigner(indexerFixture.address)

      // Get allocation
      allocationId = indexerFixture.legacyAllocations[0].allocationID
    })

    it('should allow creating and accepting indexing disputes', async () => {
      // Create an indexing dispute
      await graphToken.connect(fisherman).approve(legacyDisputeManager.target, disputeDeposit)
      await legacyDisputeManager.connect(fisherman).createIndexingDispute(allocationId, disputeDeposit)
      const disputeId = generateLegacyIndexingDisputeId(allocationId)

      // Verify dispute was created
      const disputeExists = await legacyDisputeManager.isDisputeCreated(disputeId)
      expect(disputeExists).to.be.true

      // Get state before slashing
      const idxSlashingPercentage = 25000n
      const indexerStakeBefore = (await staking.getServiceProvider(indexer.address)).tokensStaked
      const slashedAmount = (indexerStakeBefore * idxSlashingPercentage) / 1_000_000n
      const fishermanBalanceBefore = await graphToken.balanceOf(fisherman.address)

      // Accept the dispute
      await legacyDisputeManager.connect(arbitrator).acceptDispute(disputeId)

      // Verify indexer was slashed for 2.5% of their stake
      const indexerStake = (await staking.getServiceProvider(indexer.address)).tokensStaked
      expect(indexerStake).to.equal(indexerStakeBefore - slashedAmount, 'Indexer stake was not slashed correctly')

      // Verify fisherman received their deposit and 50% of the slashed amount
      const fishermanBalance = await graphToken.balanceOf(fisherman.address)
      expect(fishermanBalance).to.equal(
        fishermanBalanceBefore + slashedAmount / 2n + disputeDeposit,
        'Fisherman balance was not updated correctly',
      )
    })
  })

  describe('Query Disputes', () => {
    let allocationPrivateKey: string
    let subgraphDeploymentId: string

    beforeEach(async () => {
      // Get Indexer
      const indexerFixture = indexers[0]
      indexer = await ethers.getSigner(indexerFixture.address)

      // Get allocation
      const allocation = indexerFixture.legacyAllocations[0]
      allocationPrivateKey = allocation.allocationPrivateKey
      subgraphDeploymentId = allocation.subgraphDeploymentID
    })

    it('should allow creating and accepting query disputes', async () => {
      // Create attestation data
      const queryHash = ethers.keccak256(ethers.toUtf8Bytes('test-query'))
      const responseHash = ethers.keccak256(ethers.toUtf8Bytes('test-response'))
      const attestationData = await generateAttestationData(
        queryHash,
        responseHash,
        subgraphDeploymentId,
        allocationPrivateKey,
        await legacyDisputeManager.getAddress(),
        chainId,
      )

      // Create a query dispute
      await graphToken.connect(fisherman).approve(legacyDisputeManager.target, disputeDeposit)
      await legacyDisputeManager.connect(fisherman).createQueryDispute(attestationData, disputeDeposit)
      const disputeId = generateLegacyQueryDisputeId(
        queryHash,
        responseHash,
        subgraphDeploymentId,
        indexer.address,
        fisherman.address,
      )

      // Verify dispute was created
      const disputeExists = await legacyDisputeManager.isDisputeCreated(disputeId)
      expect(disputeExists).to.be.true

      // Get state before slashing
      const qrySlashingPercentage = 25000n
      const indexerStakeBefore = (await staking.getServiceProvider(indexer.address)).tokensStaked
      const slashedAmount = (indexerStakeBefore * qrySlashingPercentage) / 1_000_000n
      const fishermanBalanceBefore = await graphToken.balanceOf(fisherman.address)

      // Accept the dispute
      await legacyDisputeManager.connect(arbitrator).acceptDispute(disputeId)

      // Verify indexer was slashed for 2.5% of their stake
      const indexerStake = (await staking.getServiceProvider(indexer.address)).tokensStaked
      expect(indexerStake).to.equal(indexerStakeBefore - slashedAmount, 'Indexer stake was not slashed correctly')

      // Verify fisherman received their deposit and 50% of the slashed amount
      const fishermanBalance = await graphToken.balanceOf(fisherman.address)
      expect(fishermanBalance).to.equal(
        fishermanBalanceBefore + slashedAmount / 2n + disputeDeposit,
        'Fisherman balance was not updated correctly',
      )
    })
  })

  describe('Query Dispute Conflict', () => {
    let allocationPrivateKey: string
    let subgraphDeploymentId: string

    beforeEach(async () => {
      // Get Indexer
      const indexerFixture = indexers[0]
      indexer = await ethers.getSigner(indexerFixture.address)

      // Get allocation
      const allocation = indexerFixture.legacyAllocations[0]
      allocationPrivateKey = allocation.allocationPrivateKey
      subgraphDeploymentId = allocation.subgraphDeploymentID
    })

    it('should allow creating conflicting query disputes', async () => {
      // Create first attestation data
      const queryHash = ethers.keccak256(ethers.toUtf8Bytes('test-query'))
      const responseHash1 = ethers.keccak256(ethers.toUtf8Bytes('test-response-1'))
      const attestationData1 = await generateAttestationData(
        queryHash,
        responseHash1,
        subgraphDeploymentId,
        allocationPrivateKey,
        await legacyDisputeManager.getAddress(),
        chainId,
      )

      // Create second attestation data with different query/response
      const responseHash2 = ethers.keccak256(ethers.toUtf8Bytes('test-response-2'))
      const attestationData2 = await generateAttestationData(
        queryHash,
        responseHash2,
        subgraphDeploymentId,
        allocationPrivateKey,
        await legacyDisputeManager.getAddress(),
        chainId,
      )

      // Create query dispute
      await legacyDisputeManager.connect(fisherman).createQueryDisputeConflict(attestationData1, attestationData2)

      // Create dispute IDs
      const disputeId1 = generateLegacyQueryDisputeId(
        queryHash,
        responseHash1,
        subgraphDeploymentId,
        indexer.address,
        fisherman.address,
      )
      const disputeId2 = generateLegacyQueryDisputeId(
        queryHash,
        responseHash2,
        subgraphDeploymentId,
        indexer.address,
        fisherman.address,
      )

      // Verify both disputes were created
      const disputeExists1 = await legacyDisputeManager.isDisputeCreated(disputeId1)
      const disputeExists2 = await legacyDisputeManager.isDisputeCreated(disputeId2)
      expect(disputeExists1).to.be.true
      expect(disputeExists2).to.be.true

      // Get state before slashing
      const qrySlashingPercentage = 25000n
      const indexerStakeBefore = (await staking.getServiceProvider(indexer.address)).tokensStaked
      const slashedAmount = (indexerStakeBefore * qrySlashingPercentage) / 1_000_000n
      const fishermanBalanceBefore = await graphToken.balanceOf(fisherman.address)

      // Accept one dispute
      await legacyDisputeManager.connect(arbitrator).acceptDispute(disputeId1)

      // Verify indexer was slashed for 2.5% of their stake
      const indexerStake = (await staking.getServiceProvider(indexer.address)).tokensStaked
      expect(indexerStake).to.equal(indexerStakeBefore - slashedAmount, 'Indexer stake was not slashed correctly')

      // Verify fisherman received 50% of the slashed amount
      const fishermanBalance = await graphToken.balanceOf(fisherman.address)
      expect(fishermanBalance).to.equal(
        fishermanBalanceBefore + slashedAmount / 2n,
        'Fisherman balance was not updated correctly',
      )
    })
  })
})
