import { task } from 'hardhat/config'
import type { HardhatRuntimeEnvironment } from 'hardhat/types'

import { buildIssuanceContractUpgradeTxs } from '../governance/issuance-upgrade'

task(
  'issuance:build-contract-upgrade',
  'Build Safe Tx Builder JSON to upgrade an issuance contract (IssuanceAllocator, RewardsEligibilityOracle, or PilotAllocation)',
)
  .addParam('contractName', 'Contract name to upgrade: IssuanceAllocator, RewardsEligibilityOracle, or PilotAllocation')
  .addParam('newImplementation', 'New implementation address for the contract')
  .addOptionalParam(
    'graphIssuanceProxyAdmin',
    'GraphIssuanceProxyAdmin address (defaults to Issuance addresses.json value for this network)',
  )
  .addOptionalParam('callData', 'Optional calldata for upgradeAndCall (defaults to 0x)', '0x')
  .addOptionalParam(
    'txBuilderTemplate',
    'Path to a Safe Tx Builder template JSON file (relative to project root or absolute)',
  )
  .addOptionalParam('outputDir', 'Directory where the Safe Tx JSON file will be written')
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre
    const chainId = hre.network.config.chainId ?? (await ethers.provider.getNetwork()).chainId

    const validContracts = ['IssuanceAllocator', 'RewardsEligibilityOracle', 'PilotAllocation']
    if (!validContracts.includes(taskArgs.contractName)) {
      throw new Error(
        `Invalid contract name: ${taskArgs.contractName}. ` + `Valid options: ${validContracts.join(', ')}`,
      )
    }

    const result = await buildIssuanceContractUpgradeTxs(
      hre,
      {
        contractName: taskArgs.contractName as 'IssuanceAllocator' | 'RewardsEligibilityOracle' | 'PilotAllocation',
        newImplementation: taskArgs.newImplementation,
        graphIssuanceProxyAdminAddress: taskArgs.graphIssuanceProxyAdmin,
        callData: taskArgs.callData,
      },
      {
        txBuilderTemplate: taskArgs.txBuilderTemplate || undefined,
        outputDir: taskArgs.outputDir || undefined,
      },
    )

    console.log('\n========== Issuance Contract Upgrade ==========', '\n')
    console.log(`Network: ${hre.network.name} (chainId=${result.chainId})`)
    console.log(`Contract: ${taskArgs.contractName}`)
    console.log(`Implementation: ${taskArgs.newImplementation}`)
    console.log(`Safe transaction batch written to: ${result.outputFile}`)
  })
