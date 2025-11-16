module.exports = {
  skipFiles: ['test/'],
  providerOptions: {
    mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
    network_id: 1337,
  },
  // Use default istanbulFolder: './coverage'
  // Exclude 'html' to avoid duplicate HTML files (lcov already generates HTML in lcov-report/)
  istanbulReporter: ['lcov', 'text', 'json'],
  configureYulOptimizer: true,
  mocha: {
    grep: '@skip-on-coverage',
    invert: true,
  },
}
