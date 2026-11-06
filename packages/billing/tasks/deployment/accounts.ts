import { task, types } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

task('print-account', 'Print addresses for an account based on the configured mnemonic')
  .addParam('num', 'Account number, default 0', 0, types.int)
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const accounts = await hre.ethers.getSigners()
    const accountNum = taskArgs.num ?? 0
    console.log(accounts[accountNum].address)
  })
