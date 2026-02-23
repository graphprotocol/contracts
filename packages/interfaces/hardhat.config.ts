import '@nomicfoundation/hardhat-toolbox'
import 'hardhat-ignore-warnings'

const config = {
  solidity: {
    compilers: [{ version: '0.8.27' }, { version: '0.7.6' }],
  },
  typechain: {
    outDir: 'types',
  },
  warnings: {
    'contracts/token-distribution/IGraphTokenLockWallet.sol': {
      default: 'off',
    },
    'contracts/toolshed/IGraphTokenLockWalletToolshed.sol': {
      default: 'off',
    },
  },
}

module.exports = config
