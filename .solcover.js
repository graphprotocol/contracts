const skipFiles = ['bancor', 'ens', 'erc1056']

module.exports = {
  providerOptions: {
    mnemonic: process.env.DEFAULT_TEST_MNEMONIC,
    network_id: 1337,
  },
  skipFiles,
  istanbulFolder: './reports/coverage',
}
