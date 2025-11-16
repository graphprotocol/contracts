import { hardhatBaseConfig } from '@graphprotocol/toolshed/hardhat'
import type { HardhatUserConfig } from 'hardhat/config'

// Issuance-specific Solidity configuration with Cancun EVM version
// Based on toolshed solidityUserConfig but with Cancun EVM target
export const issuanceSolidityConfig = {
  version: '0.8.27',
  settings: {
    optimizer: {
      enabled: true,
      runs: 100,
    },
    evmVersion: 'cancun' as const,
  },
}

// Base configuration for issuance package - inherits from toolshed and overrides Solidity config
export const issuanceBaseConfig = (() => {
  const baseConfig = hardhatBaseConfig(require)
  return {
    ...baseConfig,
    solidity: issuanceSolidityConfig,
  } as HardhatUserConfig
})()
