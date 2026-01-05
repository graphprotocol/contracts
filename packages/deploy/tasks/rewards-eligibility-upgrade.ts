import { task } from 'hardhat/config'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import path from 'path'

import { buildRewardsEligibilityUpgradeTxs } from '../governance/rewards-eligibility-upgrade'
import { EnhancedIssuanceAddressBook } from '../lib/enhanced-address-book'

task(
  'issuance:build-rewards-eligibility-upgrade',
  'Build Safe Tx Builder JSON to upgrade RewardsManager and wire RewardsEligibilityOracle / IssuanceAllocator',
)
  .addOptionalParam(
    'rewardsManagerImplementation',
    'New RewardsManager implementation address (defaults to pending implementation if available)',
  )
  .addOptionalParam(
    'rewardsManagerAddress',
    'RewardsManager proxy address (defaults to Horizon address book value for this network)',
  )
  .addOptionalParam(
    'graphProxyAdmin',
    'GraphProxyAdmin address (defaults to Horizon address book value for this network)',
  )
  .addOptionalParam(
    'rewardsEligibilityOracleAddress',
    'RewardsEligibilityOracle proxy address (defaults to Issuance addresses.json value for this network)',
  )
  .addOptionalParam(
    'txBuilderTemplate',
    'Path to a Safe Tx Builder template JSON file (relative to project root or absolute)',
  )
  .addOptionalParam('outputDir', 'Directory where the Safe Tx JSON file will be written')
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre
    const chainId = hre.network.config.chainId ?? (await ethers.provider.getNetwork()).chainId

    // Require explicit RewardsManager implementation address
    const implementationAddress = taskArgs.rewardsManagerImplementation

    if (!implementationAddress) {
      throw new Error(
        'RewardsManager implementation address is required. ' +
          'Provide --rewards-manager-implementation parameter with the new implementation address.',
      )
    }

    const result = await buildRewardsEligibilityUpgradeTxs(
      hre,
      {
        rewardsManagerImplementation: implementationAddress,
        rewardsManagerAddress: taskArgs.rewardsManagerAddress,
        graphProxyAdmin: taskArgs.graphProxyAdmin,
        rewardsEligibilityOracleAddress: taskArgs.rewardsEligibilityOracleAddress,
      },
      {
        txBuilderTemplate: taskArgs.txBuilderTemplate || undefined,
        outputDir: taskArgs.outputDir || undefined,
      },
    )

    console.log('\n========== Issuance Rewards Eligibility Upgrade ==========', '\n')
    console.log(`Network: ${hre.network.name} (chainId=${result.chainId})`)
    console.log(`Implementation: ${implementationAddress}`)
    console.log(`Safe transaction batch written to: ${result.outputFile}`)
  })

