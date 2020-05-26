import { BuidlerConfig, task, usePlugin } from '@nomiclabs/buidler/config'

usePlugin('@nomiclabs/buidler-waffle')

// This is a sample Buidler task. To learn how to create your own go to
// https://buidler.dev/guides/create-task.html
task('accounts', 'Prints the list of accounts', async (taskArgs, bre) => {
  const accounts = await bre.ethers.getSigners()

  for (const account of accounts) {
    console.log(await account.getAddress())
  }
})

// You have to export an object to set up your config
// This object can have the following optional entries:
// defaultNetwork, networks, solc, and paths.
// Go to https://buidler.dev/config/ to learn more
const config: BuidlerConfig = {
  paths: {
    sources: './contracts',
    tests: './test',
    artifacts: './build/contracts',
  },
  solc: {
    version: '0.6.4',
    optimizer: {
      enabled: true,
      runs: 500,
    },
  },
  defaultNetwork: 'buidlerevm',
  networks: {
    buidlerevm: {
      chainId: 31337,
      loggingEnabled: true,
      gas: 'auto',
      gasPrice: 'auto',
      blockGasLimit: 9500000,
    },
    ganache: {
      chainId: 1337,
      url: 'http://localhost:8545',
    },
  },
}

export default config
