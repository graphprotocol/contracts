const skipFiles = ['bancor', 'ens', 'erc1056', 'arbitrum', 'tests/arbitrum']

module.exports = {
  providerOptions: {
    mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
    network_id: 1337,
  },
  skipFiles,
  istanbulFolder: '../coverage',
  // Remove 'html' reporter to avoid duplicates, keep lcov for lcov.info
  istanbulReporter: ['lcov', 'text', 'json'],
  configureYulOptimizer: true,
  mocha: {
    grep: '@skip-on-coverage',
    invert: true,
  },
}
