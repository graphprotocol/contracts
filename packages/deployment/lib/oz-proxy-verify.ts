import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import path from 'node:path'

/**
 * OpenZeppelin TransparentUpgradeableProxy verification utilities.
 *
 * OZ proxies are pre-compiled at a fixed Solidity version (0.8.27) that may not match
 * the project config. This module provides direct Etherscan API verification using
 * Standard JSON Input built from the installed OZ package sources.
 *
 * Uses Etherscan API V2 unified endpoint for all chains.
 */

const require = createRequire(import.meta.url)

/** Etherscan API V2 unified endpoint (for all chains) */
const ETHERSCAN_API_V2_URL = 'https://api.etherscan.io/v2/api'

/** Browser URLs for verified contract links */
const ETHERSCAN_BROWSER_URLS: Record<number, string> = {
  1: 'https://etherscan.io',
  42161: 'https://arbiscan.io',
  421614: 'https://sepolia.arbiscan.io',
}

/**
 * OZ TransparentUpgradeableProxy compiler settings (from OZ v5.4.0)
 */
const OZ_COMPILER_VERSION = 'v0.8.27+commit.40a35a09'
const OZ_COMPILER_SETTINGS = {
  optimizer: {
    enabled: true,
    runs: 200,
  },
  evmVersion: 'cancun', // Use cancun for broader compatibility (prague may not be supported)
  outputSelection: {
    '*': {
      '*': ['abi', 'evm.bytecode', 'evm.deployedBytecode', 'evm.methodIdentifiers', 'metadata'],
      '': ['ast'],
    },
  },
}

/**
 * Source files required for TransparentUpgradeableProxy verification.
 * Paths are relative to @openzeppelin/contracts package.
 */
const OZ_PROXY_SOURCE_FILES = [
  'proxy/transparent/TransparentUpgradeableProxy.sol',
  'proxy/transparent/ProxyAdmin.sol',
  'proxy/ERC1967/ERC1967Proxy.sol',
  'proxy/ERC1967/ERC1967Utils.sol',
  'proxy/Proxy.sol',
  'proxy/beacon/IBeacon.sol',
  'interfaces/IERC1967.sol',
  'utils/Address.sol',
  'utils/Errors.sol',
  'utils/StorageSlot.sol',
  'access/Ownable.sol',
  'utils/Context.sol',
]

/**
 * Read an OZ contract source file from node_modules
 */
function readOZSource(relativePath: string): string {
  const ozPackagePath = path.dirname(require.resolve('@openzeppelin/contracts/package.json'))
  const fullPath = path.join(ozPackagePath, relativePath)
  return readFileSync(fullPath, 'utf-8')
}

/**
 * Build Standard JSON Input for OZ TransparentUpgradeableProxy verification
 */
export function buildOZProxyStandardJsonInput(): string {
  const sources: Record<string, { content: string }> = {}

  for (const relativePath of OZ_PROXY_SOURCE_FILES) {
    const sourcePath = `@openzeppelin/contracts/${relativePath}`
    sources[sourcePath] = {
      content: readOZSource(relativePath),
    }
  }

  const standardJson = {
    language: 'Solidity',
    sources,
    settings: OZ_COMPILER_SETTINGS,
  }

  return JSON.stringify(standardJson)
}

/**
 * Get Etherscan API V2 URL (unified endpoint for all chains)
 */
export function getApiUrl(): string {
  return ETHERSCAN_API_V2_URL
}

/**
 * Get Etherscan browser URL for a chain
 */
export function getEtherscanBrowserUrl(chainId: number): string {
  const url = ETHERSCAN_BROWSER_URLS[chainId]
  if (!url) {
    throw new Error(`No Etherscan browser URL configured for chainId ${chainId}`)
  }
  return url
}

/**
 * Verify OZ TransparentUpgradeableProxy via Etherscan API
 *
 * @param address - Proxy contract address
 * @param constructorArgs - ABI-encoded constructor arguments (without 0x prefix is fine)
 * @param apiKey - Etherscan API key
 * @param chainId - Chain ID
 * @returns Verification result with URL if successful
 */
export async function verifyOZProxy(
  address: string,
  constructorArgs: string,
  apiKey: string,
  chainId: number,
): Promise<{ success: boolean; url?: string; message?: string }> {
  const apiUrl = getApiUrl()
  const browserUrl = getEtherscanBrowserUrl(chainId)

  // Build standard JSON input from OZ sources
  const sourceCode = buildOZProxyStandardJsonInput()

  // Strip 0x prefix from constructor args if present
  const args = constructorArgs.startsWith('0x') ? constructorArgs.slice(2) : constructorArgs

  // Build params - V2 API requires chainid in URL query string, not POST body
  const params = new URLSearchParams({
    apikey: apiKey,
    module: 'contract',
    action: 'verifysourcecode',
    contractaddress: address,
    sourceCode,
    codeformat: 'solidity-standard-json-input',
    contractname:
      '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy',
    compilerversion: OZ_COMPILER_VERSION,
    constructorArguements: args, // Note: Etherscan API has this typo
  })

  console.log(`    📤 Submitting verification to Etherscan API V2 (chainId: ${chainId})`)

  // V2 API: chainid must be in URL query string
  const submitUrl = `${apiUrl}?chainid=${chainId}`
  const submitResponse = await fetch(submitUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  })

  const submitResult = (await submitResponse.json()) as { status: string; result: string; message?: string }

  if (submitResult.status !== '1') {
    // Check if already verified (case-insensitive, handles various API response formats)
    if (submitResult.result?.toLowerCase().includes('already verified')) {
      const url = `${browserUrl}/address/${address}#code`
      return { success: true, url, message: 'Already verified' }
    }
    return { success: false, message: submitResult.result || submitResult.message || 'Unknown error' }
  }

  const guid = submitResult.result
  console.log(`    ⏳ Verification submitted, GUID: ${guid}`)

  // Poll for verification result
  const maxAttempts = 10
  const pollInterval = 3000 // 3 seconds

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    await new Promise((resolve) => setTimeout(resolve, pollInterval))

    const checkParams = new URLSearchParams({
      apikey: apiKey,
      module: 'contract',
      action: 'checkverifystatus',
      guid,
    })

    // V2 API: chainid must be in URL query string
    const checkResponse = await fetch(`${apiUrl}?chainid=${chainId}&${checkParams.toString()}`)
    const checkResult = (await checkResponse.json()) as { status: string; result: string }

    if (checkResult.result === 'Pending in queue') {
      console.log(`    ⏳ Verification pending (attempt ${attempt + 1}/${maxAttempts})...`)
      continue
    }

    if (checkResult.status === '1' || checkResult.result === 'Pass - Verified') {
      const url = `${browserUrl}/address/${address}#code`
      return { success: true, url }
    }

    // Verification failed
    return { success: false, message: checkResult.result }
  }

  return { success: false, message: 'Verification timed out' }
}
