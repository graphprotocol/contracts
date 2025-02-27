import hre, { ethers } from 'hardhat'
import { randomHexBytes, mergeABIs } from '@graphprotocol/sdk'
import { indexers } from './fixtures/indexers'
import { allocations } from './fixtures/allocations'
import { delegators } from './fixtures/delegators'
import * as fs from 'fs'
import * as path from 'path'
import { BigNumber } from 'ethers'

// The account on Arbitrum Sepolia that has GRT tokens
const GRT_HOLDER_ADDRESS = process.env.GRT_HOLDER_ADDRESS || '0xadE6B8EB69a49B56929C1d4F4b428d791861dB6f'

// Load ABIs
const stakingABI = require(path.join(__dirname, './abis/L2Staking.json'))
const stakingExtensionABI = require(path.join(__dirname, './abis/StakingExtension.json'))
const combinedStakingABI = mergeABIs(stakingABI, stakingExtensionABI)
const graphTokenABI = require(path.join(__dirname, './abis/L2GraphToken.json'))

// Generate allocation proof with the indexer's address and the allocation id, signed by the allocation private key
function generateAllocationProof(indexerAddress: string, allocationPrivateKey: string) {
  const wallet = new ethers.Wallet(allocationPrivateKey)
  const messageHash = ethers.utils.solidityKeccak256(
    ['address', 'address'],
    [indexerAddress, wallet.address],
  )
  const messageHashBytes = ethers.utils.arrayify(messageHash)
  return wallet.signMessage(messageHashBytes)
}

async function main() {
  console.log('Setting up pre horizon upgrade state...')

  console.log('\n--- STEP 0: Setup ---')

  // Verify that hardhat network accounts are set to remote, otherwise we won't be able to impersonate them
  if (hre.network.config.accounts !== 'remote') {
    throw new Error('Hardhat network accounts must be set to remote')
  }

  // Load contract addresses from addresses.json
  const addressesPath = path.join(__dirname, '../../../addresses.json')
  const addressesJson = JSON.parse(fs.readFileSync(addressesPath, 'utf8'))
  const arbSepoliaAddresses = addressesJson['421614']

  // Get contract addresses
  const stakingAddress = arbSepoliaAddresses.L2Staking.address
  const graphTokenAddress = arbSepoliaAddresses.L2GraphToken.address

  console.log(`Using Staking contract at: ${stakingAddress}`)
  console.log(`Using GraphToken contract at: ${graphTokenAddress}`)

  // Create contract instances
  const GraphToken = new ethers.Contract(graphTokenAddress, graphTokenABI, ethers.provider)
  const Staking = new ethers.Contract(stakingAddress, combinedStakingABI, ethers.provider)

  // The account on Arbitrum Sepolia that has GRT tokens
  const assetHolderBalance = await GraphToken.balanceOf(GRT_HOLDER_ADDRESS)
  console.log(`Asset holder balance: ${assetHolderBalance}`)
  
  // Impersonate the account
  await ethers.provider.send('hardhat_impersonateAccount', [GRT_HOLDER_ADDRESS])
  const grtHolder = await ethers.getSigner(GRT_HOLDER_ADDRESS)

  // STEP 1: Fund and stake for indexers
  console.log('\n--- STEP 1: Indexers Staking ---')
  for (const indexer of indexers) {
    // Fund the indexer using the impersonated account
    console.log(`Funding indexer ${indexer.address}...`)
    const transferTx = await GraphToken.connect(grtHolder).transfer(indexer.address, indexer.stake)
    await transferTx.wait()
    await hre.network.provider.send('hardhat_setBalance', [indexer.address, '0x56BC75E2D63100000']) // 100 Eth

    // Approve and stake
    console.log(`Staking ${indexer.stake} tokens for indexer ${indexer.address}...`)
    const approveTx = await GraphToken.connect(await ethers.getSigner(indexer.address)).approve(Staking.address, indexer.stake)
    await approveTx.wait()
    const stakeTx = await Staking.connect(await ethers.getSigner(indexer.address)).stake(indexer.stake)
    await stakeTx.wait()
  }

  // STEP 2: Fund and delegate for delegators
  console.log('\n--- STEP 2: Delegators Delegating ---')
  for (const delegator of delegators) {
    // Calculate total tokens needed for this delegator
    const totalDelegationTokens = delegator.delegations.reduce(
      (sum, delegation) => sum.add(delegation.tokens),
      BigNumber.from(0)
    )
    
    // Fund the delegator using the impersonated account
    console.log(`Funding delegator ${delegator.address}...`)
    const delegatorFundTx = await GraphToken.connect(grtHolder).transfer(delegator.address, totalDelegationTokens)
    await delegatorFundTx.wait()
    await hre.network.provider.send('hardhat_setBalance', [delegator.address, '0x56BC75E2D63100000']) // 100 Eth

    // Delegate to each indexer
    for (const delegation of delegator.delegations) {
      console.log(`Delegating ${delegation.tokens} tokens from ${delegator.address} to indexer ${delegation.indexerAddress}...`)
      const delegationApproveTx = await GraphToken.connect(await ethers.getSigner(delegator.address)).approve(Staking.address, delegation.tokens)
      await delegationApproveTx.wait()
      const delegateTx = await Staking.connect(await ethers.getSigner(delegator.address)).delegate(delegation.indexerAddress, delegation.tokens)
      await delegateTx.wait()
    }
  }

  // STEP 3: Create allocations
  console.log('\n--- STEP 3: Creating Allocations ---')
  for (const allocation of allocations) {
    console.log(`Creating allocation of ${allocation.tokens} tokens from indexer ${allocation.indexerAddress} on subgraph ${allocation.subgraphDeploymentID}...`)
    
    const allocateTx = await Staking.connect(await ethers.getSigner(allocation.indexerAddress)).allocate(
      allocation.subgraphDeploymentID,
      allocation.tokens,
      allocation.allocationID,
      randomHexBytes(), // metadata
      await generateAllocationProof(allocation.indexerAddress, allocation.allocationPrivateKey)
    )
    await allocateTx.wait()
  }

  // STEP 4: One delegator undelegates
  console.log('\n--- STEP 4: Undelegating ---')
  for (const delegator of delegators) {
    if (delegator.undelegate) {
      console.log(`Delegator ${delegator.address} is undelegating...`)
      
      for (const delegation of delegator.delegations) {
        // Get the delegation information
        const delegationInfo = await Staking.getDelegation(delegation.indexerAddress, delegator.address)
        const shares = delegationInfo.shares
        
        console.log(`Undelegating ${shares} shares from indexer ${delegation.indexerAddress}...`)

        // Undelegate the shares
        const undelegateTx = await Staking.connect(await ethers.getSigner(delegator.address)).undelegate(delegation.indexerAddress, shares)
        await undelegateTx.wait()
      }
    }
  }

  // Stop impersonating the account
  await hre.network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [GRT_HOLDER_ADDRESS],
  });

  console.log('\nPre-upgrade state setup complete!')
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
