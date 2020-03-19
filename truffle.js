const fs = require('fs')
const path = require('path')
const HDWalletProvider = require('truffle-hdwallet-provider')
const utils = require('web3-utils')

// noMultisigDevelopement and noMultisigRopsten allow for quick testing of the contracts
// i.e. no thawing period, no multisig

module.exports = {
  networks: {
    development: {
      host: '127.0.0.1', // Localhost (default: none)
      port: 8545, // Standard Ethereum port (default: none)
      network_id: '*', // Any network (default: none)
      skipDryRun: true,
    },
    noMultisigDevelopment: {
      host: '127.0.0.1', // Localhost (default: none)
      port: 8545, // Standard Ethereum port (default: none)
      network_id: '3859', // Any network (default: none)
      skipDryRun: true,
    },
    kovan: {
      provider: () =>
        new HDWalletProvider(
          fs
            .readFileSync(__dirname + '/.privkey.txt')
            .toString()
            .trim(),
          `https://kovan.infura.io/v3/${fs
            .readFileSync(__dirname + '/.infurakey.txt')
            .toString()
            .trim()}`,
        ),
      network_id: 42, // kovan's id
      gas: 8000000,
      skipDryRun: true,
      from: '0x93606b27cB5e4c780883eC4F6b7Bed5f6572d1dd',
    },
    ropsten: {
      provider: () =>
        new HDWalletProvider(
          fs
            .readFileSync(__dirname + '/.privkey.txt')
            .toString()
            .trim(),
          `https://ropsten.infura.io/v3/${fs
            .readFileSync(__dirname + '/.infurakey.txt')
            .toString()
            .trim()}`,
        ),
      network_id: 3, // Ropsten's id
      gas: 8000000,
      gasPrice: utils.toWei('10', 'gwei'),
      skipDryRun: true,
    },
    noMultisigRopsten: {
      provider: () =>
        new HDWalletProvider(
          fs.readFileSync(path.join(__dirname, '.privkey.txt'), 'utf-8').trim(),
          `https://ropsten.infura.io/v3/${fs
            .readFileSync(path.join(__dirname, '/.infurakey.txt'), 'utf-8')
            .trim()}`,
          0,
          2,
        ),
      network_id: 3, // Ropsten's id
      gas: 8000000,
      gasPrice: utils.toWei('10', 'gwei'),
      skipDryRun: true,
    },
  },

  compilers: {
    solc: {
      version: '0.6.4', // Fetch exact version from solc-bin (default: truffle's version)
      // docker: true,     // Use "0.5.1" you've installed locally with docker (default: false)
      settings: {
        // See the solidity docs for advice about optimization and evmVersion
        optimizer: {
          enabled: true,
          runs: 500,
        },
      },
    },
  },
}
