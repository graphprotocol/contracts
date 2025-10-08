const skipFiles = ['bancor', 'ens', 'erc1056', 'arbitrum', 'tests/arbitrum']

module.exports = {
  providerOptions: {
    mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
    network_id: 1337,
  },
  skipFiles,
  // Use default istanbulFolder: './coverage'
  // Remove 'html' reporter to avoid duplicates, keep lcov for lcov.info
  istanbulReporter: ['lcov', 'text', 'json'],
  configureYulOptimizer: true,
  mocha: {
    grep: '@skip-on-coverage',
    invert: true,
  },
  onCompileComplete: async function (/* config */) {
    // Set environment variable to indicate we're running under coverage
    process.env.SOLIDITY_COVERAGE = 'true'
  },
  onIstanbulComplete: async function (/* config */) {
    // Clean up environment variable
    delete process.env.SOLIDITY_COVERAGE
  },
}
