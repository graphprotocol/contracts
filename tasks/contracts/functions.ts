import { Wallet } from 'ethers'
import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

import { loadEnv } from '../../cli/env'

task('contracts:functions', 'Print function hashes for contracts').setAction(
  async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const accounts = await hre.ethers.getSigners()
    const env = await loadEnv(taskArgs, accounts[0] as unknown as Wallet)

    console.log('## Staking ##')
    for (const fn of Object.entries(env.contracts.Staking.functions)) {
      const [fnSig] = fn
      if (fnSig.indexOf('(') != -1) {
        console.log(fnSig, '->', hre.ethers.utils.id(fnSig).slice(0, 10))
      }
    }
  },
)
