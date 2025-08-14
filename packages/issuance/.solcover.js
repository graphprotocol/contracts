module.exports = {
  skipFiles: ['test/'],
  providerOptions: {
    mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
    network_id: 1337,
  },
  istanbulFolder: './test/reports/coverage',
  configureYulOptimizer: true,
  mocha: {
    grep: '@skip-on-coverage',
    invert: true,
  },
  reporter: ['html', 'lcov', 'text'],
  reporterOptions: {
    html: {
      directory: './test/reports/coverage/html',
    },
  },
}
