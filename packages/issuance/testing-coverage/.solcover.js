module.exports = {
  skipFiles: ['test/'],
  mocha: {
    require: ['tsx'],
    loader: 'tsx',
  },
  configureYulOptimizer: true,
  solcOptimizerDetails: {
    yul: true,
    yulDetails: {
      optimizerSteps: '',
    },
  },
}
