import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

task('accounts', 'Prints the list of accounts', async (_, hre: HardhatRuntimeEnvironment) => {
  const accounts = await hre.ethers.getSigners()
  for (const account of accounts) {
    console.log(await account.getAddress())
  }
})
