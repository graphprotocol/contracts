const skipFiles = ['bancor', 'ens', 'erc1056', 'arbitrum', 'tests/arbitrum']

module.exports = {
  providerOptions: {
    mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
    network_id: 1337,
  },
  skipFiles,
  istanbulFolder: './reports/coverage',
  configureYulOptimizer: true,
}
