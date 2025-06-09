// Test-focused Hardhat configuration
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import '@typechain/hardhat'
import 'dotenv/config'
import 'hardhat-dependency-compiler'
import 'hardhat-gas-reporter'
import 'solidity-coverage'
// Test-specific tasks
import './tasks/migrate/nitro'
import './tasks/test-upgrade'

import { configDir } from '@graphprotocol/contracts'
import fs from 'fs'
import { HardhatUserConfig } from 'hardhat/config'
import path from 'path'

// Default mnemonic for testing
const DEFAULT_TEST_MNEMONIC = 'myth like bonus scare over problem client lizard pioneer submit female collect'

// Recursively find all .sol files in a directory
function findSolidityFiles(dir: string): string[] {
  const files: string[] = []

  function walkDir(currentDir: string): void {
    const entries = fs.readdirSync(currentDir, { withFileTypes: true })

    for (const entry of entries) {
      const fullPath = path.join(currentDir, entry.name)

      if (entry.isDirectory()) {
        walkDir(fullPath)
      } else if (entry.isFile() && entry.name.endsWith('.sol')) {
        files.push(fullPath)
      }
    }
  }

  walkDir(dir)
  return files
}

// Dynamically find all Solidity files in @graphprotocol/contracts
function getContractPaths(): string[] {
  const contractsDir = path.resolve(__dirname, '../contracts')

  if (!fs.existsSync(contractsDir)) {
    throw new Error(`Contracts directory not found: ${contractsDir}`)
  }

  const files = findSolidityFiles(contractsDir)

  if (files.length === 0) {
    throw new Error(`No Solidity files found in: ${contractsDir}`)
  }

  const contractPaths = files.map((file: string) => {
    // Convert absolute path to @graphprotocol/contracts relative path
    const relativePath = path.relative(contractsDir, file)
    return `@graphprotocol/contracts/contracts/${relativePath}`
  })

  console.log(`Found ${contractPaths.length} Solidity files for dependency compilation`)

  // // Log first few files for debugging
  // console.log('Sample files:')
  // contractPaths.slice(0, 5).forEach((p: string) => console.log(`  ${p}`))
  // if (contractPaths.length > 5) {
  //   console.log(`  ... and ${contractPaths.length - 5} more`)
  // }

  return contractPaths
}

const config: HardhatUserConfig = {
  graph: {
    addressBook: process.env.ADDRESS_BOOK || 'addresses.json',
    disableSecureAccounts: true,
  },
  solidity: {
    compilers: [
      {
        version: '0.7.6',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  paths: {
    tests: './tests/unit',
    cache: './cache',
    graph: '..',
  },
  typechain: {
    outDir: 'types',
  },
  dependencyCompiler: {
    paths: getContractPaths(),
  },
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: {
      chainId: 1337,
      loggingEnabled: false,
      gas: 12000000,
      gasPrice: 'auto',
      initialBaseFeePerGas: 0,
      blockGasLimit: 12000000,
      accounts: {
        mnemonic: DEFAULT_TEST_MNEMONIC,
      },
      hardfork: 'london',
      // Graph Protocol extensions
      graphConfig: path.join(configDir, 'graph.hardhat.yml'),
      addressBook: process.env.ADDRESS_BOOK || 'addresses.json',
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any,
    localhost: {
      chainId: 1337,
      url: 'http://127.0.0.1:8545',
      accounts: { mnemonic: DEFAULT_TEST_MNEMONIC },
    },
  },

  gasReporter: {
    enabled: process.env.REPORT_GAS ? true : false,
    showTimeSpent: true,
    currency: 'USD',
    outputFile: 'reports/gas-report.log',
  },
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
} as any

export default config
