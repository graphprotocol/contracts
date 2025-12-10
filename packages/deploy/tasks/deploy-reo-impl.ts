import { task } from 'hardhat/config'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import path from 'path'

import { buildIssuanceContractUpgradeTxs } from '../governance/issuance-upgrade'
import { EnhancedIssuanceAddressBook } from '../lib/enhanced-address-book'

/**
 * Deploy new RewardsEligibilityOracle implementation with automated orchestration
 *
 * This task:
 * 1. Deploys new RewardsEligibilityOracle implementation contract
 * 2. Marks it as pending in the address book
 * 3. Auto-generates Safe TX JSON for governance (GraphIssuanceProxyAdmin.upgrade)
 * 4. Prints next steps for governance execution
 *
 * Usage:
 *   npx hardhat issuance:deploy-reo-impl --network arbitrumOne
 *   npx hardhat issuance:deploy-reo-impl --network arbitrumSepolia
 */
task(
  'issuance:deploy-reo-impl',
  'Deploy new RewardsEligibilityOracle implementation and prepare for governance upgrade',
)
  .addOptionalParam('outputDir', 'Directory where the Safe Tx JSON file will be written')
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const { ethers, ignition } = hre
    const chainId = hre.network.config.chainId ?? (await ethers.provider.getNetwork()).chainId

    console.log('\n========== Deploy RewardsEligibilityOracle Implementation ==========\n')
    console.log(`Network: ${hre.network.name} (chainId=${chainId})`)

    // Step 1: Deploy new RewardsEligibilityOracle implementation
    console.log('\n📦 Step 1: Deploying new RewardsEligibilityOracle implementation...')

    const RewardsEligibilityOracleImplementationModule = await import(
      '@graphprotocol/issuance/deploy/ignition/modules/RewardsEligibilityOracleImplementation'
    )
    const { RewardsEligibilityOracleImplementation } = await ignition.deploy(
      RewardsEligibilityOracleImplementationModule.default,
    )

    const implAddress = await RewardsEligibilityOracleImplementation.getAddress()
    const deployTx = RewardsEligibilityOracleImplementation.deploymentTransaction()

    console.log(`✅ Implementation deployed: ${implAddress}`)
    if (deployTx) {
      console.log(`   Transaction: ${deployTx.hash}`)
    }

    // Step 2: Load address book and mark as pending
    console.log('\n📝 Step 2: Marking as pending in address book...')

    const issuanceAddressBookPath = path.resolve(__dirname, '../../issuance/addresses.json')

    const addressBook = new EnhancedIssuanceAddressBook(issuanceAddressBookPath, Number(chainId))

    addressBook.setPendingImplementation('RewardsEligibilityOracle', implAddress, {
      txHash: deployTx?.hash,
      readyForUpgrade: true,
    })

    console.log('✅ Pending implementation recorded in address book')
    console.log(`   Address book: ${issuanceAddressBookPath}`)

    // Step 3: Auto-generate governance TX
    console.log('\n⚙️  Step 3: Generating governance transaction batch...')

    const result = await buildIssuanceContractUpgradeTxs(
      hre,
      {
        contractName: 'RewardsEligibilityOracle',
        newImplementation: implAddress,
      },
      {
        outputDir: taskArgs.outputDir || undefined,
      },
    )

    console.log(`✅ Safe TX JSON generated: ${result.outputFile}`)

    // Summary and next steps
    console.log('\n========== Deployment Complete ==========\n')
    console.log('📊 Summary:')
    console.log(`   Implementation: ${implAddress}`)
    console.log(`   Status: Pending governance approval`)
    console.log(`   Safe TX file: ${result.outputFile}`)

    console.log('\n🎯 Next Steps:')
    console.log('   1. Review the Safe TX file to verify transaction details')
    console.log(`   2. Upload ${path.basename(result.outputFile)} to Safe UI`)
    console.log('   3. Obtain multi-sig approval signatures')
    console.log('   4. Execute the transaction via Safe')
    console.log('   5. After execution, sync the address book:')
    console.log(
      `      npx hardhat issuance:sync-pending-implementation --contract RewardsEligibilityOracle --network ${hre.network.name}`,
    )

    console.log('\n💡 Tip: You can check pending implementations with:')
    console.log(`   npx hardhat issuance:list-pending --network ${hre.network.name}`)
  })
