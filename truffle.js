const fs = require ('fs')
const HDWalletProvider = require('truffle-hdwallet-provider');
const infuraKey = fs.readFileSync(".infurakey.txt").toString().trim();
const mnemonic = fs.readFileSync(".privkey.txt").toString().trim();

module.exports = {
  networks: {
    development: {
      host: "127.0.0.1",     // Localhost (default: none)
      port: 8545,            // Standard Ethereum port (default: none)
      network_id: "*",       // Any network (default: none)
    },

    kovan: {
      provider: () => new HDWalletProvider(mnemonic, `https://kovan.infura.io/v3/${infuraKey}`),
      network_id: 42,      // kovan's id
      gas: 6000000,
      skipDryRun: true,
      from: "0x93606b27cB5e4c780883eC4F6b7Bed5f6572d1dd",
    },
    ropsten: {
      provider: () => new HDWalletProvider(mnemonic, `https://ropsten.infura.io/v3/${infuraKey}`),
      network_id: 3,      // Ropsten's id
      gas: 6000000,
      skipDryRun: true,
      from: "0x93606b27cB5e4c780883eC4F6b7Bed5f6572d1dd",
    },
  },

  compilers: {
    solc: {
      version: "0.5.2",    // Fetch exact version from solc-bin (default: truffle's version)
      // docker: true,     // Use "0.5.1" you've installed locally with docker (default: false)
      settings: {          // See the solidity docs for advice about optimization and evmVersion
        optimizer: {
          enabled: true,
          runs: 500,
        },
      },
    },
  },
};
