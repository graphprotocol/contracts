import hre, { ethers } from 'hardhat'
import { Contract } from 'ethers'
import { mergeABIs } from 'hardhat-graph-protocol/sdk'
import { indexers } from './fixtures/indexers'
import { delegators } from './fixtures/delegators'

import { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'

import L2StakingABI from '@graphprotocol/contracts/build/abis/L2Staking.json'
import StakingExtensionABI from '@graphprotocol/contracts/build/abis/StakingExtension.json'
import L2GraphTokenABI from '@graphprotocol/contracts/build/abis/L2GraphToken.json'

import { IGraphToken, IStaking } from '@graphprotocol/contracts'

// The account on Arbitrum Sepolia that has GRT tokens
const GRT_HOLDER_ADDRESS = process.env.GRT_HOLDER_ADDRESS || '0xadE6B8EB69a49B56929C1d4F4b428d791861dB6f'

// Load ABIs
const combinedStakingABI = mergeABIs(L2StakingABI, StakingExtensionABI)
const graphTokenABI = L2GraphTokenABI

// Generate allocation proof with the indexer's address and the allocation id, signed by the allocation private key
function generateAllocationProof(indexerAddress: string, allocationPrivateKey: string) {
  const wallet = new ethers.Wallet(allocationPrivateKey)
  const messageHash = ethers.solidityPackedKeccak256(
    ['address', 'address'],
    [indexerAddress, wallet.address],
  )
  const messageHashBytes = ethers.getBytes(messageHash)
  return wallet.signMessage(messageHashBytes)
}

const randomHexBytes = (n = 32): string => ethers.hexlify(ethers.randomBytes(n))

async function main() {
  console.log(getBanner())

  console.log('\n--- STEP 0: Setup ---')

  // Verify that hardhat network accounts are set to remote, otherwise we won't be able to impersonate them
  if (hre.network.config.accounts !== 'remote') {
    throw new Error('Hardhat network accounts must be set to remote')
  }

  // Load contract addresses from addresses.json
  const addressesJson = require('@graphprotocol/contracts/addresses.json')
  const arbSepoliaAddresses = addressesJson['421614']

  // Get contract addresses
  const stakingAddress = arbSepoliaAddresses.L2Staking.address
  const graphTokenAddress = arbSepoliaAddresses.L2GraphToken.address

  console.log(`Using Staking contract at: ${stakingAddress}`)
  console.log(`Using GraphToken contract at: ${graphTokenAddress}`)

  // Create contract instances
  const provider = new HardhatEthersProvider(hre.network.provider, hre.network.name)
  const GraphToken = new Contract(graphTokenAddress, graphTokenABI, provider) as unknown as IGraphToken
  const Staking = new Contract(stakingAddress, combinedStakingABI, provider) as unknown as IStaking

  // The account on Arbitrum Sepolia that has GRT tokens
  const assetHolderBalance = await GraphToken.balanceOf(GRT_HOLDER_ADDRESS)
  console.log(`Asset holder balance: ${assetHolderBalance}`)

  // Convert BigNumber to bigint for comparison
  if (BigInt(assetHolderBalance.toString()) < ethers.parseEther('20000000')) {
    throw new Error('Asset holder balance is less than 20M tokens')
  }
  
  // Impersonate the account
  const grtHolder = await ethers.getImpersonatedSigner(GRT_HOLDER_ADDRESS) as any

  // Fund with GRT signers from 0 to 19 with 1M tokens
  console.log('Funding signers from 0 to 19 with 1M tokens...')
  const signers = await ethers.getSigners()
  for (let i = 0; i < 20; i++) {
    const signer = signers[i]
    const transferTx = await GraphToken.connect(grtHolder).transfer(signer.address, ethers.parseEther('1000000'))
    await transferTx.wait()
  }

  // STEP 1: Fund and stake for indexers
  console.log('\n--- STEP 1: Indexers Setup ---')
  for (const indexer of indexers) {
    // Impersonate the indexer
    const indexerSigner = await ethers.getSigner(indexer.address) as any

    // Approve and stake
    console.log(`Staking ${indexer.stake} tokens for indexer ${indexer.address}...`)
    const approveTx = await GraphToken.connect(indexerSigner).approve(stakingAddress, indexer.stake)
    await approveTx.wait()
    const stakeTx = await Staking.connect(indexerSigner).stake(indexer.stake)
    await stakeTx.wait()

    // Set delegation parameters
    console.log(`Setting delegation parameters for indexer ${indexer.address}...`)
    const setDelegationParametersTx = await Staking.connect(indexerSigner).setDelegationParameters(indexer.indexingRewardCut, indexer.queryFeeCut, 0)
    await setDelegationParametersTx.wait()

    // Set rewards destination if it exists
    if (indexer.rewardsDestination) {
      console.log(`Setting rewards destination for indexer ${indexer.address} to ${indexer.rewardsDestination}...`)
      const setRewardsDestinationTx = await Staking.connect(indexerSigner).setRewardsDestination(indexer.rewardsDestination)
      await setRewardsDestinationTx.wait()
    }
  }

  // STEP 2: Fund and delegate for delegators
  console.log('\n--- STEP 2: Delegators Delegating ---')
  for (const delegator of delegators) {
    // Impersonate the delegator
    const delegatorSigner = await ethers.getSigner(delegator.address) as any

    // Delegate to each indexer
    for (const delegation of delegator.delegations) {
      console.log(`Delegating ${delegation.tokens} tokens from ${delegator.address} to indexer ${delegation.indexerAddress}...`)
      const delegationApproveTx = await GraphToken.connect(delegatorSigner).approve(stakingAddress, delegation.tokens)
      await delegationApproveTx.wait()
      const delegateTx = await Staking.connect(delegatorSigner).delegate(delegation.indexerAddress, delegation.tokens)
      await delegateTx.wait()
    }
  }

  // STEP 3: Create allocations
  console.log('\n--- STEP 3: Creating Allocations ---')
  for (const indexer of indexers) {
    // Impersonate the indexer
    const indexerSigner = await ethers.getSigner(indexer.address) as any

    for (const allocation of indexer.allocations) {
      console.log(`Creating allocation of ${allocation.tokens} tokens from indexer ${indexer.address} on subgraph ${allocation.subgraphDeploymentID}...`)
      
      const allocateTx = await Staking.connect(indexerSigner).allocate(
        allocation.subgraphDeploymentID,
        allocation.tokens,
        allocation.allocationID,
        randomHexBytes(), // metadata
        await generateAllocationProof(indexer.address, allocation.allocationPrivateKey)
      )
      await allocateTx.wait()
    }
  }

  // STEP 4: Indexer unstakes
  console.log('\n--- STEP 4: Indexer unstakes ---')
  for (const indexer of indexers) {
    if (indexer.tokensToUnstake) {
      console.log(`Indexer ${indexer.address} is unstaking...`)
      const indexerSigner = await ethers.getSigner(indexer.address) as any
      const unstakeTx = await Staking.connect(indexerSigner).unstake(indexer.tokensToUnstake)
      await unstakeTx.wait()
    }
  }

  // STEP 5: Undelegate
  console.log('\n--- STEP 5: Undelegating ---')
  for (const delegator of delegators) {
    if (delegator.undelegate) {
      console.log(`Delegator ${delegator.address} is undelegating...`)

      // Impersonate the delegator
      const delegatorSigner = await ethers.getSigner(delegator.address) as any
      
      for (const delegation of delegator.delegations) {
        // Get the delegation information
        const delegationInfo = await Staking.getDelegation(delegation.indexerAddress, delegator.address)
        const shares = delegationInfo.shares
        
        console.log(`Undelegating ${shares} shares from indexer ${delegation.indexerAddress}...`)

        // Undelegate the shares
        const undelegateTx = await Staking.connect(delegatorSigner).undelegate(delegation.indexerAddress, shares)
        await undelegateTx.wait()
      }
    }
  }
  
  console.log('\n\n🎉 ✨ 🚀 ✅ Pre-upgrade state setup complete! 🎉 ✨ 🚀 ✅\n')
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exitCode = 1
  })

function getBanner() {
  return `
+-----------------------------------------------+
|                                               |
|           PRE-HORIZON UPGRADE SETUP           |
|                                               |
+-----------------------------------------------+
  `
}
