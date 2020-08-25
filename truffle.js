// Needed for truffle flattener
module.exports = {
  compilers: {
    solc: {
      version: '0.6.4',
      settings: {
        optimizer: {
          enabled: true,
          runs: 200,
        },
      },
    },
  },
}
