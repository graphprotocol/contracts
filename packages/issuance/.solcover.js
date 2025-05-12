module.exports = {
  skipFiles: [],
  providerOptions: {
    mnemonic: 'myth like bonus scare over problem client lizard pioneer submit female collect',
    network_id: 1337,
  },
  istanbulFolder: './reports/coverage',
  configureYulOptimizer: true,
  mocha: {
    grep: "@skip-on-coverage",
    invert: true,
  },
};
