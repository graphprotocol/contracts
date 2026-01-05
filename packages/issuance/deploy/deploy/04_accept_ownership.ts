import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import type { DeployFunction } from 'hardhat-deploy/types'

/**
 * Accept ownership of all issuance contracts
 *
 * This is a governance operation that should be run after initial deployment.
 * Each issuance contract uses Ownable2Step, which requires the new owner to
 * explicitly accept ownership via acceptOwnership().
 *
 * This script is idempotent - it checks current ownership and only calls
 * acceptOwnership() if:
 * 1. The governor is the pending owner (ownership transfer initiated)
 * 2. The governor is not yet the current owner
 *
 * Governance pattern:
 * 1. Contracts deployed with initialize(governor) - sets governor as pending owner
 * 2. Governor calls acceptOwnership() - completes ownership transfer
 * 3. Governor becomes current owner and can manage the contracts
 *
 * This separation ensures:
 * - Atomic initialization prevents front-running
 * - Explicit acceptance confirms governor control
 * - Two-step process follows OpenZeppelin best practices
 *
 * Usage:
 *   pnpm hardhat deploy --tags accept-ownership --network <network>
 *
 * Or as part of full deployment:
 *   pnpm hardhat deploy --tags issuance --network <network>
 */
const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, ethers } = hre
  const { log, read, execute } = deployments
  const { governor } = await getNamedAccounts()

  const contracts = ['IssuanceAllocator', 'PilotAllocation', 'RewardsEligibilityOracle']

  log('Checking ownership status for issuance contracts...')

  for (const contractName of contracts) {
    const deployment = await deployments.getOrNull(contractName)
    if (!deployment) {
      log(`Skipping ${contractName} - not deployed`)
      continue
    }

    try {
      // Check current owner
      const currentOwner = (await read(contractName, 'owner')) as string

      // Check if governor is already the owner
      if (currentOwner.toLowerCase() === governor.toLowerCase()) {
        log(`${contractName}: Governor is already the owner`)
        continue
      }

      // Check pending owner
      const pendingOwner = (await read(contractName, 'pendingOwner')) as string

      // Check if governor is the pending owner
      if (pendingOwner.toLowerCase() === governor.toLowerCase()) {
        log(`${contractName}: Accepting ownership as governor...`)
        await execute(contractName, { from: governor, log: true }, 'acceptOwnership')
        log(`${contractName}: Ownership accepted`)
      } else {
        log(`${contractName}: Governor is not the pending owner (pending: ${pendingOwner})`)
      }
    } catch (error) {
      log(`${contractName}: Error checking/accepting ownership: ${error}`)
    }
  }

  log('Ownership acceptance complete')
}

func.tags = ['accept-ownership', 'issuance-governance', 'issuance']
func.dependencies = ['issuance-core'] // Requires all core contracts to be deployed
func.runAtTheEnd = true // Run after all other deployments
func.id = 'AcceptOwnership'

export default func
