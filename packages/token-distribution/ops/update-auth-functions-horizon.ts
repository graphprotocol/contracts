import consola from 'consola'
import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

import { askConfirm, getTokenLockManagerOrFail, prettyEnv, waitTransaction } from './create'
import { TxBuilder } from './tx-builder'

const logger = consola.create({})

task('update-auth-functions-horizon', 'Update authorized functions for Horizon upgrade')
  .addParam('horizonStakingAddress', 'Address of the HorizonStaking contract')
  .addParam('subgraphServiceAddress', 'Address of the SubgraphService contract')
  .addParam('managerName', 'Name of the token lock manager deployment', 'GraphTokenLockManager')
  .addFlag('txBuilder', 'Output transaction batch in JSON format for Safe multisig')
  .addOptionalParam('txBuilderTemplate', 'File to use as a template for the transaction builder')
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const manager = await getTokenLockManagerOrFail(hre, taskArgs.managerName)

    logger.info('Updating authorized functions for Horizon upgrade...')
    logger.log(`> GraphTokenLockManager: ${manager.address}`)
    logger.log(`> HorizonStaking: ${taskArgs.horizonStakingAddress}`)
    logger.log(`> SubgraphService: ${taskArgs.subgraphServiceAddress}`)

    logger.log(await prettyEnv(hre))

    // Functions to ADD for HorizonStaking
    const horizonStakingFunctionsToAdd = [
      'provisionLocked(address,address,uint256,uint32,uint64)',
      'thaw(address,address,uint256)',
      'deprovision(address,address,uint256)',
      'setDelegationFeeCut(address,address,uint8,uint256)',
      'setOperatorLocked(address,address,bool)',
      'withdrawDelegated(address,address,uint256)',
    ]

    // Functions to ADD for SubgraphService
    const subgraphServiceFunctionsToAdd = ['setPaymentsDestination(address)']

    // Functions to REMOVE for old Staking contract
    const functionsToRemove = [
      'setDelegationParameters(uint32,uint32,uint32)',
      'setOperator(address,bool)',
      'setRewardsDestination(address)',
    ]

    logger.info('\n=== Functions to be ADDED ===')
    logger.info('For HorizonStaking:')
    horizonStakingFunctionsToAdd.forEach((sig) => logger.log(`  + ${sig}`))
    logger.info('\nFor SubgraphService:')
    subgraphServiceFunctionsToAdd.forEach((sig) => logger.log(`  + ${sig}`))

    logger.info('\n=== Functions to be REMOVED ===')
    functionsToRemove.forEach((sig) => logger.log(`  - ${sig}`))

    // Check if not using tx-builder that deployer is the manager owner
    if (!taskArgs.txBuilder) {
      const tokenLockManagerOwner = await manager.owner()
      const { deployer } = await hre.getNamedAccounts()
      if (tokenLockManagerOwner !== deployer) {
        logger.error('Only the owner can update authorized functions')
        process.exit(1)
      }
      logger.success(`\nDeployer is the manager owner: ${deployer}`)
    }

    // Confirm before proceeding
    logger.info('\n=== Summary ===')
    logger.info(`Functions to remove: ${functionsToRemove.length}`)
    logger.info(`Functions to add for HorizonStaking: ${horizonStakingFunctionsToAdd.length}`)
    logger.info(`Functions to add for SubgraphService: ${subgraphServiceFunctionsToAdd.length}`)

    if (!(await askConfirm())) {
      logger.log('Cancelled')
      process.exit(1)
    }

    if (taskArgs.txBuilder) {
      // Generate tx-builder JSON for Safe multisig
      logger.info('\nCreating transaction builder JSON file for Safe multisig...')
      const chainId = (await hre.ethers.provider.getNetwork()).chainId.toString()
      const txBuilder = new TxBuilder(chainId, taskArgs.txBuilderTemplate)

      // Add transactions to remove old functions
      logger.log('\nBuilding transactions to remove old functions...')
      for (const signature of functionsToRemove) {
        const tx = await manager.populateTransaction.unsetAuthFunctionCall(signature)
        txBuilder.addTx({
          to: manager.address,
          value: '0',
          data: tx.data,
        })
        logger.log(`  - Remove: ${signature}`)
      }

      // Add transactions to add HorizonStaking functions
      logger.log('\nBuilding transactions to add HorizonStaking functions...')
      const horizonTargets = Array(horizonStakingFunctionsToAdd.length).fill(taskArgs.horizonStakingAddress)
      const tx1 = await manager.populateTransaction.setAuthFunctionCallMany(
        horizonStakingFunctionsToAdd,
        horizonTargets,
      )
      txBuilder.addTx({
        to: manager.address,
        value: '0',
        data: tx1.data,
      })
      logger.log(`  + Added ${horizonStakingFunctionsToAdd.length} functions for HorizonStaking`)

      // Add transactions to add SubgraphService functions
      logger.log('\nBuilding transactions to add SubgraphService functions...')
      const subgraphTargets = Array(subgraphServiceFunctionsToAdd.length).fill(taskArgs.subgraphServiceAddress)
      const tx2 = await manager.populateTransaction.setAuthFunctionCallMany(
        subgraphServiceFunctionsToAdd,
        subgraphTargets,
      )
      txBuilder.addTx({
        to: manager.address,
        value: '0',
        data: tx2.data,
      })
      logger.log(`  + Added ${subgraphServiceFunctionsToAdd.length} functions for SubgraphService`)

      // Add token destinations if needed
      logger.log('\nChecking and adding token destinations if needed...')

      // Check if HorizonStaking is already a token destination
      const isHorizonStakingDestination = await manager.isTokenDestination(taskArgs.horizonStakingAddress)
      if (!isHorizonStakingDestination) {
        const tx3 = await manager.populateTransaction.addTokenDestination(taskArgs.horizonStakingAddress)
        txBuilder.addTx({
          to: manager.address,
          value: '0',
          data: tx3.data,
        })
        logger.log(`  + Add HorizonStaking as token destination`)
      } else {
        logger.log(`  ✓ HorizonStaking already added as token destination`)
      }

      // Check if SubgraphService is already a token destination
      const isSubgraphServiceDestination = await manager.isTokenDestination(taskArgs.subgraphServiceAddress)
      if (!isSubgraphServiceDestination) {
        const tx4 = await manager.populateTransaction.addTokenDestination(taskArgs.subgraphServiceAddress)
        txBuilder.addTx({
          to: manager.address,
          value: '0',
          data: tx4.data,
        })
        logger.log(`  + Add SubgraphService as token destination`)
      } else {
        logger.log(`  ✓ SubgraphService already added as token destination`)
      }

      // Save result into json file
      const outputFile = txBuilder.saveToFile()
      logger.success(`\nTransaction batch saved to ${outputFile}`)
      logger.info('\nUpload this file to your Safe multisig to execute the transactions.')

      // Summary
      logger.info('\n=== SUMMARY ===')
      logger.info(`Total transactions: ${txBuilder.contents.transactions.length}`)
      logger.info(`  - Remove functions: ${functionsToRemove.length}`)
      logger.info(`  - Add HorizonStaking functions: 1 batch (${horizonStakingFunctionsToAdd.length} functions)`)
      logger.info(`  - Add SubgraphService functions: 1 batch (${subgraphServiceFunctionsToAdd.length} functions)`)
      const destinationsAdded = (!isHorizonStakingDestination ? 1 : 0) + (!isSubgraphServiceDestination ? 1 : 0)
      logger.info(`  - Add token destinations: ${destinationsAdded}`)
    } else {
      // Execute transactions
      logger.info('\nExecuting transactions...')

      // Remove old functions
      logger.info('\nRemoving old functions...')
      for (const signature of functionsToRemove) {
        try {
          logger.log(`  Removing: ${signature}`)
          const tx = await manager.unsetAuthFunctionCall(signature)
          await waitTransaction(tx)
          logger.success(`  ✓ Removed: ${signature}`)
        } catch (error) {
          logger.error(`  ✗ Failed to remove ${signature}: ${error.message}`)
          process.exit(1)
        }
      }

      // Add HorizonStaking functions
      logger.info('\nAdding HorizonStaking functions...')
      try {
        const horizonTargets = Array(horizonStakingFunctionsToAdd.length).fill(taskArgs.horizonStakingAddress)
        const tx = await manager.setAuthFunctionCallMany(horizonStakingFunctionsToAdd, horizonTargets)
        await waitTransaction(tx)
        logger.success(`  ✓ Added ${horizonStakingFunctionsToAdd.length} functions for HorizonStaking`)
      } catch (error) {
        logger.error(`  ✗ Failed to add HorizonStaking functions: ${error.message}`)
        process.exit(1)
      }

      // Add SubgraphService functions
      logger.info('\nAdding SubgraphService functions...')
      try {
        const subgraphTargets = Array(subgraphServiceFunctionsToAdd.length).fill(taskArgs.subgraphServiceAddress)
        const tx = await manager.setAuthFunctionCallMany(subgraphServiceFunctionsToAdd, subgraphTargets)
        await waitTransaction(tx)
        logger.success(`  ✓ Added ${subgraphServiceFunctionsToAdd.length} functions for SubgraphService`)
      } catch (error) {
        logger.error(`  ✗ Failed to add SubgraphService functions: ${error.message}`)
        process.exit(1)
      }

      // Add token destinations if needed
      logger.info('\nChecking and adding token destinations if needed...')

      // Check if HorizonStaking is already a token destination
      const isHorizonStakingDestination = await manager.isTokenDestination(taskArgs.horizonStakingAddress)
      if (!isHorizonStakingDestination) {
        try {
          logger.log(`  Adding HorizonStaking as token destination...`)
          const tx = await manager.addTokenDestination(taskArgs.horizonStakingAddress)
          await waitTransaction(tx)
          logger.success(`  ✓ Added HorizonStaking as token destination`)
        } catch (error) {
          logger.error(`  ✗ Failed to add HorizonStaking as token destination: ${error.message}`)
          process.exit(1)
        }
      } else {
        logger.success(`  ✓ HorizonStaking already a token destination`)
      }

      // Check if SubgraphService is already a token destination
      const isSubgraphServiceDestination = await manager.isTokenDestination(taskArgs.subgraphServiceAddress)
      if (!isSubgraphServiceDestination) {
        try {
          logger.log(`  Adding SubgraphService as token destination...`)
          const tx = await manager.addTokenDestination(taskArgs.subgraphServiceAddress)
          await waitTransaction(tx)
          logger.success(`  ✓ Added SubgraphService as token destination`)
        } catch (error) {
          logger.error(`  ✗ Failed to add SubgraphService as token destination: ${error.message}`)
          process.exit(1)
        }
      } else {
        logger.success(`  ✓ SubgraphService already a token destination`)
      }

      // Summary
      logger.info('\n=== COMPLETED SUCCESSFULLY ===')
      logger.info(`Removed ${functionsToRemove.length} old functions`)
      logger.info(`Added ${horizonStakingFunctionsToAdd.length} functions for HorizonStaking`)
      logger.info(`Added ${subgraphServiceFunctionsToAdd.length} functions for SubgraphService`)
      const destinationsAdded = (!isHorizonStakingDestination ? 1 : 0) + (!isSubgraphServiceDestination ? 1 : 0)
      logger.info(`Added ${destinationsAdded} token destinations`)
    }
  })
