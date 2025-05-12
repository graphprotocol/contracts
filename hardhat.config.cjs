require('@nomicfoundation/hardhat-ethers');
require('@nomicfoundation/hardhat-verify');
require('@nomicfoundation/hardhat-chai-matchers');
require('@typechain/hardhat');
require('hardhat-abi-exporter');
require('hardhat-contract-sizer');
require('hardhat-gas-reporter');
require('solidity-coverage');

const dotenv = require('dotenv');
const { HardhatUserConfig } = require('hardhat/config');

dotenv.config();

// Config
const config = {
  paths: {
    sources: './contracts',
    tests: './test',
    artifacts: './build/contracts',
  },
  solidity: {
    compilers: [
      {
        version: '0.8.27',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          outputSelection: {
            '*': {
              '*': ['storageLayout'],
            },
          },
        },
      },
    ],
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
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS ? true : false,
    showTimeSpent: true,
    currency: 'USD',
    outputFile: 'reports/gas-report.log',
  },
  typechain: {
    outDir: 'build/types',
    target: 'ethers-v6',
  },
  abiExporter: {
    path: './build/abis',
    clear: true,
    flat: true,
    runOnCompile: true,
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: false,
    disambiguatePaths: false,
  },
};

module.exports = config;
