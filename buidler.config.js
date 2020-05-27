const buidler = require('@nomiclabs/buidler/config')
const usePlugin = buidler.usePlugin

usePlugin('@nomiclabs/buidler-truffle5')

const config = {
  paths: {
    sources: './contracts',
    tests: './test',
    artifacts: './build',
  },
  solc: {
    version: '0.6.4', // Note that this only has the version number
  },
  defaultNetwork: 'buidlerevm',
  networks: {
    ganache: {
      chainId: 4447,
      url: 'http://localhost:8545',
    },
    buidlerevm: {
      loggingEnabled: false,
    },
  },
}

module.exports = config
