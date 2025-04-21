import { encodeLegacyAllocationProof, randomAllocationMetadata } from '@graphprotocol/toolshed'
import { requireLocalNetwork, setGRTBalance } from '@graphprotocol/toolshed/hardhat'
import { delegators } from './fixtures/delegators'
import { indexers } from './fixtures/indexers'
import { printBanner } from '@graphprotocol/toolshed/utils'
import { task } from 'hardhat/config'

task('test:seed', 'Sets up some protocol state for testing')
  .setAction(async (_, hre) => {
    printBanner('PROTOCOL STATE SETUP')

    console.log('\n--- STEP 0: Setup ---')

    // this task uses impersonation so we NEED a local network
    requireLocalNetwork(hre)

    // Get contracts
    const graph = hre.graph()
    const GraphToken = graph.horizon.contracts.L2GraphToken
    const Staking = graph.horizon.contracts.LegacyStaking

    // STEP 1: stake for indexers
    console.log('\n--- STEP 1: Indexers Setup ---')
    for (const indexer of indexers) {
      await setGRTBalance(graph.provider, GraphToken.target, indexer.address, indexer.stake)

      // Impersonate the indexer
      const indexerSigner = await hre.ethers.getImpersonatedSigner(indexer.address)

      // Approve and stake
      console.log(`Staking ${indexer.stake} tokens for indexer ${indexer.address}...`)
      await GraphToken.connect(indexerSigner).approve(Staking.target, indexer.stake)
      await Staking.connect(indexerSigner).stake(indexer.stake)

      // Set delegation parameters
      console.log(`Setting delegation parameters for indexer ${indexer.address}...`)
      await Staking.connect(indexerSigner).setDelegationParameters(indexer.indexingRewardCut, indexer.queryFeeCut, 0)

      // Set rewards destination if it exists
      if (indexer.rewardsDestination) {
        console.log(`Setting rewards destination for indexer ${indexer.address} to ${indexer.rewardsDestination}...`)
        await Staking.connect(indexerSigner).setRewardsDestination(indexer.rewardsDestination)
      }
    }

    // STEP 2: Fund and delegate for delegators
    console.log('\n--- STEP 2: Delegators Delegating ---')
    for (const delegator of delegators) {
      await setGRTBalance(graph.provider, GraphToken.target, delegator.address, delegator.delegations.reduce((acc, d) => acc + d.tokens, BigInt(0)))

      // Impersonate the delegator
      const delegatorSigner = await hre.ethers.getImpersonatedSigner(delegator.address)

      // Delegate to each indexer
      for (const delegation of delegator.delegations) {
        console.log(`Delegating ${delegation.tokens} tokens from ${delegator.address} to indexer ${delegation.indexerAddress}...`)
        await GraphToken.connect(delegatorSigner).approve(Staking.target, delegation.tokens)
        await Staking.connect(delegatorSigner).delegate(delegation.indexerAddress, delegation.tokens)
      }
    }

    // STEP 3: Create allocations
    console.log('\n--- STEP 3: Creating Allocations ---')
    for (const indexer of indexers) {
      // Impersonate the indexer
      const indexerSigner = await hre.ethers.getImpersonatedSigner(indexer.address)

      for (const allocation of indexer.allocations) {
        console.log(`Creating allocation of ${allocation.tokens} tokens from indexer ${indexer.address} on subgraph ${allocation.subgraphDeploymentID}...`)

        await Staking.connect(indexerSigner).allocate(
          allocation.subgraphDeploymentID,
          allocation.tokens,
          allocation.allocationID,
          randomAllocationMetadata(),
          await encodeLegacyAllocationProof(indexer.address, allocation.allocationPrivateKey),
        )
      }
    }

    // STEP 4: Indexer unstakes
    console.log('\n--- STEP 4: Indexer unstakes ---')
    for (const indexer of indexers) {
      if (indexer.tokensToUnstake) {
        console.log(`Indexer ${indexer.address} is unstaking...`)

        // Impersonate the indexer
        const indexerSigner = await hre.ethers.getImpersonatedSigner(indexer.address)

        // Unstake
        await Staking.connect(indexerSigner).unstake(indexer.tokensToUnstake)
      }
    }

    // STEP 5: Undelegate
    console.log('\n--- STEP 5: Undelegating ---')
    for (const delegator of delegators) {
      if (delegator.undelegate) {
        console.log(`Delegator ${delegator.address} is undelegating...`)

        // Impersonate the delegator
        const delegatorSigner = await hre.ethers.getImpersonatedSigner(delegator.address)

        for (const delegation of delegator.delegations) {
          // Get the delegation information
          const delegationInfo = await Staking.getDelegation(delegation.indexerAddress, delegator.address)
          const shares = BigInt(delegationInfo.shares.toString())

          console.log(`Undelegating ${shares} shares from indexer ${delegation.indexerAddress}...`)

          // Undelegate the shares
          await Staking.connect(delegatorSigner).undelegate(delegation.indexerAddress, shares)
        }
      }
    }

    console.log('\n\n🎉 ✨ 🚀 ✅ Pre-upgrade state setup complete! 🎉 ✨ 🚀 ✅\n')
  })
