import { configVariable } from 'hardhat/config'

/**
 * Convert network name to env var prefix: arbitrumSepolia → ARBITRUM_SEPOLIA
 */
export function networkToEnvPrefix(networkName: string): string {
  return networkName.replace(/([a-z])([A-Z])/g, '$1_$2').toUpperCase()
}

/**
 * Resolve a configuration variable from environment.
 *
 * For deploy scripts that need config values at runtime (like API keys),
 * keystore values must be exported to environment first:
 *
 *   export ARBISCAN_API_KEY=$(npx hardhat keystore get ARBISCAN_API_KEY)
 *
 * Note: Deployer/governor keys in network config use configVariable() which
 * Hardhat resolves automatically via the keystore plugin. This function is
 * for runtime values that aren't part of network config.
 *
 * @param name - Configuration variable name (e.g., 'ARBISCAN_API_KEY')
 * @returns The resolved value or undefined if not set
 */
export async function resolveConfigVar(name: string): Promise<string | undefined> {
  const envValue = process.env[name]
  if (envValue) {
    return envValue
  }
  return undefined
}

/**
 * Get deployer key name for a network.
 * Always uses network-specific key (e.g., ARBITRUM_SEPOLIA_DEPLOYER_KEY).
 */
export function getDeployerKeyName(networkName: string): string {
  const prefix = networkToEnvPrefix(networkName)
  return `${prefix}_DEPLOYER_KEY`
}

/**
 * Get governor key name for a network.
 * Always uses network-specific key (e.g., ARBITRUM_SEPOLIA_GOVERNOR_KEY).
 */
export function getGovernorKeyName(networkName: string): string {
  const prefix = networkToEnvPrefix(networkName)
  return `${prefix}_GOVERNOR_KEY`
}
