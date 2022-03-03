import { Wallet } from 'ethers'
import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import '@nomiclabs/hardhat-ethers'
import 'hardhat-storage-layout'

import { loadEnv } from '../../cli/env'
import { cliOpts } from '../../cli/defaults'

task('contracts:functions', 'Print function hashes for contracts')
  .addParam('addressBook', cliOpts.addressBook.description, cliOpts.addressBook.default)
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const accounts = await hre.ethers.getSigners()
    const env = await loadEnv(taskArgs, accounts[0] as unknown as Wallet)

    console.log('## Staking ##')
    for (const fn of Object.entries(env.contracts.Staking.functions)) {
      const [fnSig] = fn
      if (fnSig.indexOf('(') != -1) {
        console.log(fnSig, '->', hre.ethers.utils.id(fnSig).slice(0, 10))
      }
    }

    console.log('## GNS ##')
    for (const fn of Object.entries(env.contracts.GNS.functions)) {
      const [fnSig] = fn
      if (fnSig.indexOf('(') != -1) {
        console.log(fnSig, '->', hre.ethers.utils.id(fnSig).slice(0, 10))
      }
    }
  })

task('contracts:layout', 'Display storage layout').setAction(async (_, hre) => {
  await hre.storageLayout.export()
})
