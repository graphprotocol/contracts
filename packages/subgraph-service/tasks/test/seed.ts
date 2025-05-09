import { task } from 'hardhat/config'

import { encodeRegistrationData, encodeStartServiceData, generateAllocationProof, generatePOI, PaymentTypes } from '@graphprotocol/toolshed'
import { HorizonStakingExtension } from '@graphprotocol/horizon'

import { indexers } from './fixtures/indexers'

task('test:seed', 'Seed the test environment, must be run after deployment')
  .setAction(async (_, hre) => {
    // Get contracts
    const graph = hre.graph()
    const horizonStaking = graph.horizon.contracts.HorizonStaking
    const horizonStakingExtension = graph.horizon.contracts.HorizonStaking as HorizonStakingExtension
    const subgraphService = graph.subgraphService.contracts.SubgraphService
    const disputeManager = graph.subgraphService.contracts.DisputeManager

    // Get contract addresses
    const subgraphServiceAddress = await subgraphService.getAddress()

    // Get chain id
    const chainId = (await hre.ethers.provider.getNetwork()).chainId

    // Get configs
    const disputePeriod = await disputeManager.getDisputePeriod()
    const maxSlashingCut = await disputeManager.maxSlashingCut()

    console.log('\n--- STEP 1: Close all legacy allocations ---')

    for (const indexer of indexers) {
      // Skip indexers with no allocations
      if (indexer.legacyAllocations.length === 0) {
        continue
      }

      console.log(`Closing allocations for indexer: ${indexer.address}`)

      // Get indexer signer
      const indexerSigner = await hre.ethers.getSigner(indexer.address)

      // Close all allocations with POI != 0
      for (const allocation of indexer.legacyAllocations) {
        console.log(`Closing allocation: ${allocation.allocationID}`)

        // Close allocation
        const poi = generatePOI()
        await horizonStakingExtension.connect(indexerSigner).closeAllocation(
          allocation.allocationID,
          poi,
        )

        const allocationData = await horizonStaking.getAllocation(allocation.allocationID)
        console.log(`Allocation closed at epoch: ${allocationData.closedAtEpoch}`)
      }
    }

    console.log('\n--- STEP 2: Create provisions, set delegation cuts and register indexers ---')

    for (const indexer of indexers) {
      // Create provision
      console.log(`Creating subgraph service provision for indexer: ${indexer.address}`)
      const indexerSigner = await hre.ethers.getSigner(indexer.address)
      await horizonStaking.connect(indexerSigner).provision(indexer.address, await subgraphService.getAddress(), indexer.provisionTokens, maxSlashingCut, disputePeriod)
      console.log(`Provision created for indexer with ${indexer.provisionTokens} tokens`)

      // Set delegation fee cut
      console.log(`Setting delegation fee cut for indexer: ${indexer.address}`)
      await horizonStaking.connect(indexerSigner).setDelegationFeeCut(indexer.address, subgraphServiceAddress, PaymentTypes.IndexingRewards, indexer.indexingRewardCut)
      await horizonStaking.connect(indexerSigner).setDelegationFeeCut(indexer.address, subgraphServiceAddress, PaymentTypes.QueryFee, indexer.queryFeeCut)

      // Register indexer
      console.log(`Registering indexer: ${indexer.address}`)
      const indexerRegistrationData = encodeRegistrationData(indexer.url, indexer.geoHash, indexer.rewardsDestination || hre.ethers.ZeroAddress)
      await subgraphService.connect(indexerSigner).register(indexerSigner.address, indexerRegistrationData)

      const indexerData = await subgraphService.indexers(indexerSigner.address)

      console.log(`Indexer registered at: ${indexerData.registeredAt}`)
    }

    console.log('\n--- STEP 3: Start allocations ---')

    for (const indexer of indexers) {
      // Skip indexers with no allocations
      if (indexer.allocations.length === 0) {
        continue
      }

      console.log(`Starting allocations for indexer: ${indexer.address}`)

      const indexerSigner = await hre.ethers.getSigner(indexer.address)

      for (const allocation of indexer.allocations) {
        console.log(`Starting allocation: ${allocation.allocationID}`)

        // Build allocation proof
        const signature = await generateAllocationProof(indexer.address, allocation.allocationPrivateKey, subgraphServiceAddress, Number(chainId))
        const subgraphDeploymentId = allocation.subgraphDeploymentID
        const allocationTokens = allocation.tokens
        const allocationId = allocation.allocationID

        // Attempt to create an allocation with the same ID
        const data = encodeStartServiceData(subgraphDeploymentId, allocationTokens, allocationId, signature)

        // Start allocation
        await subgraphService.connect(indexerSigner).startService(
          indexerSigner.address,
          data,
        )

        console.log(`Allocation started with tokens: ${allocationTokens}`)
      }
    }
  })
