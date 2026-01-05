import type { HardhatRuntimeEnvironment } from 'hardhat/types'
import type { DeployFunction } from 'hardhat-deploy/types'

/**
 * Configure IssuanceAllocator initial state
 *
 * This script performs the initial configuration of IssuanceAllocator:
 * 1. Optionally sets issuance rate to match RewardsManager (if available)
 * 2. Optionally configures RewardsManager as self-minting target
 * 3. Calls distributeIssuance() to initialize distribution state
 * 4. Grants PAUSE_ROLE to designated pause guardian
 *
 * This script is idempotent - it checks current state before making changes.
 *
 * Configuration options via tags:
 * - configure-issuance-rate: Set issuance rate from RewardsManager
 * - configure-rewards-manager: Add RewardsManager as self-minting target
 *
 * Requirements:
 * - IssuanceAllocator must be deployed
 * - Governor account must have GOVERNOR_ROLE
 * - pauseGuardian account must be configured in namedAccounts
 *
 * Usage:
 *   # Full configuration
 *   pnpm hardhat deploy --tags configure-issuance --network <network>
 *
 *   # Just pause role setup
 *   pnpm hardhat deploy --tags configure-issuance-pause --network <network>
 */
const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, ethers } = hre
  const { execute, read, log } = deployments
  const { governor } = await getNamedAccounts()

  const pauseGuardian = await getNamedAccounts().then((accounts) => accounts.pauseGuardian || governor)

  // Get IssuanceAllocator deployment
  const issuanceAllocator = await deployments.get('IssuanceAllocator')
  log(`Configuring IssuanceAllocator at ${issuanceAllocator.address}`)

  // Check if already configured
  const currentRate = (await read('IssuanceAllocator', 'getIssuancePerBlock')) as bigint
  const isPaused = (await read('IssuanceAllocator', 'paused')) as boolean

  // 1. Set issuance rate if needed (optional - only if RewardsManager deployment exists)
  const shouldConfigureRate = hre.deployments.getOrNull('RewardsManager').then((rm) => rm !== null)
  if ((await shouldConfigureRate) && currentRate === 0n) {
    try {
      const rewardsManagerRate = (await read('RewardsManager', 'issuancePerBlock')) as bigint
      if (rewardsManagerRate > 0n) {
        log(`Setting issuance rate to match RewardsManager: ${rewardsManagerRate}`)
        await execute('IssuanceAllocator', { from: governor, log: true }, 'setIssuancePerBlock', rewardsManagerRate)
        log('✓ Issuance rate configured')
      } else {
        log('⚠ RewardsManager rate is 0, skipping rate configuration')
      }
    } catch (error) {
      log('⚠ Could not read RewardsManager rate, skipping rate configuration')
    }
  } else if (currentRate > 0n) {
    log(`✓ Issuance rate already set: ${currentRate}`)
  } else {
    log('⚠ Issuance rate is 0 (will be configured later via governance)')
  }

  // 2. Configure RewardsManager as self-minting target if requested
  const shouldConfigureRM = hre.deployments.getOrNull('RewardsManager').then((rm) => rm !== null)
  if (await shouldConfigureRM) {
    try {
      const rewardsManager = await deployments.get('RewardsManager')
      const rmAllocation = (await read('IssuanceAllocator', 'getTargetAllocation', rewardsManager.address)) as {
        allocatorMintingRate: bigint
        selfMintingRate: bigint
      }

      if (rmAllocation.selfMintingRate === 0n && currentRate > 0n) {
        log(`Configuring RewardsManager as self-minting target: ${rewardsManager.address}`)
        await execute(
          'IssuanceAllocator',
          { from: governor, log: true },
          'setTargetAllocation',
          rewardsManager.address,
          0, // allocatorMintingRate (RM self-mints)
          currentRate, // selfMintingRate (100% allocation)
          false, // evenIfDistributionPending
        )
        log('✓ RewardsManager configured as self-minting target')
      } else {
        log('✓ RewardsManager already configured or rate not set')
      }
    } catch (error) {
      log('⚠ Could not configure RewardsManager allocation, skipping')
    }
  }

  // 3. Initialize distribution state
  const lastDistributionBlock = (await read('IssuanceAllocator', 'lastDistributionBlock')) as bigint
  const currentBlock = BigInt((await ethers.provider.getBlockNumber()) as number)

  if (lastDistributionBlock < currentBlock) {
    log(`Calling distributeIssuance() to initialize state (last: ${lastDistributionBlock}, current: ${currentBlock})`)
    try {
      await execute('IssuanceAllocator', { from: governor, log: true }, 'distributeIssuance')
      log('✓ Distribution state initialized')
    } catch (error) {
      log('⚠ distributeIssuance() failed (may be paused or have no allocations)')
    }
  } else {
    log('✓ Distribution already current')
  }

  // 4. Grant PAUSE_ROLE to pause guardian
  const pauseRole = (await read('IssuanceAllocator', 'PAUSE_ROLE')) as string
  const hasPauseRole = (await read('IssuanceAllocator', 'hasRole', pauseRole, pauseGuardian)) as boolean

  if (!hasPauseRole) {
    log(`Granting PAUSE_ROLE to pause guardian: ${pauseGuardian}`)
    await execute('IssuanceAllocator', { from: governor, log: true }, 'grantRole', pauseRole, pauseGuardian)
    log('✓ PAUSE_ROLE granted')
  } else {
    log(`✓ Pause guardian already has PAUSE_ROLE: ${pauseGuardian}`)
  }

  // Verify contract is not paused
  if (isPaused) {
    log('⚠ WARNING: IssuanceAllocator is PAUSED')
  } else {
    log('✓ IssuanceAllocator is not paused')
  }

  log('IssuanceAllocator configuration complete')
}

func.tags = ['configure-issuance', 'configure-issuance-allocator']
func.dependencies = ['issuance-allocator', 'pilot-allocation', 'rewards-eligibility-oracle']
func.runAtTheEnd = true

export default func
