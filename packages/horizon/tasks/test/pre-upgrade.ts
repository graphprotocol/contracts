import { Contract } from 'ethers'
import { task } from 'hardhat/config'

import { HardhatEthersProvider } from '@nomicfoundation/hardhat-ethers/internal/hardhat-ethers-provider'

import ControllerABI from '@graphprotocol/contracts/build/abis/Controller.json'
import L2GraphTokenABI from '@graphprotocol/contracts/build/abis/L2GraphToken.json'
import L2StakingABI from '@graphprotocol/contracts/build/abis/L2Staking.json'
import StakingExtensionABI from '@graphprotocol/contracts/build/abis/StakingExtension.json'

import { IController, IGraphToken, IStaking } from '@graphprotocol/contracts'
import { mergeABIs } from 'hardhat-graph-protocol/sdk'
import { printBanner } from 'hardhat-graph-protocol/sdk'

import { delegators } from './fixtures/delegators'
import { indexers } from './fixtures/indexers'

// Load ABIs
const combinedStakingABI = mergeABIs(L2StakingABI, StakingExtensionABI)
const graphTokenABI = L2GraphTokenABI
const controllerABI = ControllerABI

task('test:integration:pre-upgrade', 'Sets up the pre-upgrade state for testing')
  .setAction(async (_, hre) => {
    printBanner('PRE-HORIZON UPGRADE SETUP')

    console.log('\n--- STEP 0: Setup ---')

    // Helper functions that use hre.ethers
    // Generate allocation proof with the indexer's address and the allocation id, signed by the allocation private key
    const generateAllocationProof = async (indexerAddress: string, allocationPrivateKey: string) => {
      const wallet = new hre.ethers.Wallet(allocationPrivateKey)
      const messageHash = hre.ethers.solidityPackedKeccak256(
        ['address', 'address'],
        [indexerAddress, wallet.address],
      )
      const messageHashBytes = hre.ethers.getBytes(messageHash)
      return wallet.signMessage(messageHashBytes)
    }

    const randomHexBytes = (n = 32): string => hre.ethers.hexlify(hre.ethers.randomBytes(n))

    // Verify that hardhat network accounts are set to remote, otherwise we won't be able to impersonate them
    if (hre.network.config.accounts !== 'remote') {
      throw new Error('Hardhat network accounts must be set to remote')
    }

    // Load contract addresses from addresses.json
    const addressesJson = require('@graphprotocol/contracts/addresses.json')
    const arbSepoliaAddresses = addressesJson['421614']

    // Get addresses
    const stakingAddress = arbSepoliaAddresses.L2Staking.address
    const graphTokenAddress = arbSepoliaAddresses.L2GraphToken.address
    const controllerAddress = arbSepoliaAddresses.Controller.address

    console.log(`Using Staking contract at: ${stakingAddress}`)
    console.log(`Using GraphToken contract at: ${graphTokenAddress}`)

    // Create contract instances
    // Note: Using ABIs directly instead of hre.graph().horizon because these are the old deployed contract instances
    const provider = new HardhatEthersProvider(hre.network.provider, hre.network.name)
    const GraphToken = new Contract(graphTokenAddress, graphTokenABI, provider) as unknown as IGraphToken
    const Staking = new Contract(stakingAddress, combinedStakingABI, provider) as unknown as IStaking
    const Controller = new Contract(controllerAddress, controllerABI, provider) as unknown as IController

    // Use account 0 as the minter
    const signers = await hre.ethers.getSigners()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const minterAccount = signers[0] as any
    console.log(`Using minter account: ${minterAccount.address}`)

    // Impersonate the governor to add minting permissions
    const governorAddress = await Controller.getGovernor()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const governorSigner = await hre.ethers.getImpersonatedSigner(governorAddress) as any

    // Add minting permissions for our minter account
    console.log(`Adding minting permissions for ${minterAccount.address}...`)
    const addMinterTx = await GraphToken.connect(governorSigner).addMinter(minterAccount.address)
    await addMinterTx.wait()
    console.log(`Successfully added minting permissions for ${minterAccount.address}`)

    // Mint tokens to our minter account
    const mintAmount = hre.ethers.parseEther('50000000') // 50M tokens
    console.log(`Minting ${mintAmount} tokens to ${minterAccount.address}...`)
    const mintTx = await GraphToken.connect(minterAccount).mint(minterAccount.address, mintAmount)
    await mintTx.wait()

    // Fund with GRT signers from 1 to 19 with 1M tokens
    console.log('Funding signers from 1 to 19 with 1M tokens...')
    for (let i = 0; i < 20; i++) {
      const signer = signers[i]
      const transferTx = await GraphToken.connect(minterAccount).transfer(signer.address, hre.ethers.parseEther('1000000'))
      await transferTx.wait()
    }

    // STEP 1: Fund and stake for indexers
    console.log('\n--- STEP 1: Indexers Setup ---')
    for (const indexer of indexers) {
      // Impersonate the indexer
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const indexerSigner = await hre.ethers.getImpersonatedSigner(indexer.address) as any

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
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const delegatorSigner = await hre.ethers.getImpersonatedSigner(delegator.address) as any

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
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const indexerSigner = await hre.ethers.getImpersonatedSigner(indexer.address) as any

      for (const allocation of indexer.allocations) {
        console.log(`Creating allocation of ${allocation.tokens} tokens from indexer ${indexer.address} on subgraph ${allocation.subgraphDeploymentID}...`)

        const allocateTx = await Staking.connect(indexerSigner).allocate(
          allocation.subgraphDeploymentID,
          allocation.tokens,
          allocation.allocationID,
          randomHexBytes(), // metadata
          await generateAllocationProof(indexer.address, allocation.allocationPrivateKey),
        )
        await allocateTx.wait()
      }
    }

    // STEP 4: Indexer unstakes
    console.log('\n--- STEP 4: Indexer unstakes ---')
    for (const indexer of indexers) {
      if (indexer.tokensToUnstake) {
        console.log(`Indexer ${indexer.address} is unstaking...`)

        // Impersonate the indexer
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const indexerSigner = await hre.ethers.getImpersonatedSigner(indexer.address) as any

        // Unstake
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
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const delegatorSigner = await hre.ethers.getImpersonatedSigner(delegator.address) as any

        for (const delegation of delegator.delegations) {
          // Get the delegation information
          const delegationInfo = await Staking.getDelegation(delegation.indexerAddress, delegator.address)
          const shares = BigInt(delegationInfo.shares.toString())

          console.log(`Undelegating ${shares} shares from indexer ${delegation.indexerAddress}...`)

          // Undelegate the shares
          const undelegateTx = await Staking.connect(delegatorSigner).undelegate(delegation.indexerAddress, shares)
          await undelegateTx.wait()
        }
      }
    }

    console.log('\n\n🎉 ✨ 🚀 ✅ Pre-upgrade state setup complete! 🎉 ✨ 🚀 ✅\n')
  })
