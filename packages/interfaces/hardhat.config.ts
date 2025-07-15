import '@nomicfoundation/hardhat-toolbox'

const config = {
  solidity: {
    compilers: [{ version: '0.8.27' }, { version: '0.7.6' }],
  },
  typechain: {
    outDir: 'types',
  },
}

module.exports = config
