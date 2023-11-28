// Needed for truffle flattener
module.exports = {
  compilers: {
    solc: {
      version: '0.7.3',
      settings: {
        optimizer: {
          enabled: true,
          runs: 200,
        },
      },
    },
  },
}
