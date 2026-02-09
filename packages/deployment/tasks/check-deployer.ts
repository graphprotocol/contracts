import { configVariable, task } from 'hardhat/config'
import type { NewTaskActionFunction } from 'hardhat/types/tasks'
import { createPublicClient, custom, formatEther } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'

const BLOCK_EXPLORERS: Record<number, string> = {
  42161: 'https://arbiscan.io/address/',
  421614: 'https://sepolia.arbiscan.io/address/',
}

/**
 * Convert network name to env var prefix: arbitrumSepolia → ARBITRUM_SEPOLIA
 */
function networkToEnvPrefix(networkName: string): string {
  return networkName.replace(/([a-z])([A-Z])/g, '$1_$2').toUpperCase()
}

/**
 * Resolve a configuration variable using Hardhat's hook chain (keystore + env fallback)
 */
async function resolveConfigVar(hre: unknown, name: string): Promise<string | undefined> {
  try {
    const variable = configVariable(name)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const hooks = (hre as any).hooks

    const value = await hooks.runHandlerChain(
      'configurationVariables',
      'fetchValue',
      [variable],
      async (_context: unknown, v: { name: string }) => {
        const envValue = process.env[v.name]
        if (typeof envValue !== 'string') {
          throw new Error(`Variable ${v.name} not found`)
        }
        return envValue
      },
    )
    return value
  } catch {
    return undefined
  }
}

interface TaskArgs {
  // No arguments for this task
}

/**
 * Check deployer account address and balance on the connected network.
 *
 * Uses the deployer key from keystore or environment variable.
 * Set via: npx hardhat keystore set ARBITRUM_SEPOLIA_DEPLOYER_KEY
 * Or: export ARBITRUM_SEPOLIA_DEPLOYER_KEY=0x...
 *
 * Usage:
 *   npx hardhat deploy:check-deployer --network arbitrumSepolia
 */
const action: NewTaskActionFunction<TaskArgs> = async (_taskArgs, hre) => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const conn = await (hre as any).network.connect()
  const networkName = conn.networkName

  // Get deployer private key from keystore or env var
  const keyName = `${networkToEnvPrefix(networkName)}_DEPLOYER_KEY`
  const privateKey = await resolveConfigVar(hre, keyName)

  if (!privateKey) {
    console.error('\nError: No deployer account configured.')
    console.error(`Set via keystore: npx hardhat keystore set ${keyName}`)
    console.error(`Or environment: export ${keyName}=0x...`)
    return
  }
  const account = privateKeyToAccount(privateKey as `0x${string}`)
  const address = account.address
  console.log(`\nDeployer address: ${address}`)
  console.log(`Network: ${networkName}`)

  // Get balance via viem public client
  const client = createPublicClient({
    transport: custom(conn.provider),
  })

  try {
    const chainId = await client.getChainId()
    const balance = await client.getBalance({ address: address as `0x${string}` })
    const balanceEth = formatEther(balance)

    console.log(`Balance: ${balanceEth} ETH`)

    if (balance === 0n) {
      console.log('\nNo funds. This account needs to be funded before deploying.')
    } else if (parseFloat(balanceEth) < 0.05) {
      console.log('\nLow balance. Recommend at least 0.1 ETH for deployments.')
    } else {
      console.log('\nSufficient balance for deployment.')
    }

    const explorerBase = BLOCK_EXPLORERS[chainId]
    if (explorerBase) {
      console.log(`\nBlock explorer: ${explorerBase}${address}`)
    }
  } catch (error) {
    console.log(`\nCould not check balance: ${(error as Error).message}`)
  }
}

const checkDeployerTask = task('deploy:check-deployer', 'Check deployer account address and balance')
  .setAction(async () => ({ default: action }))
  .build()

export default checkDeployerTask
