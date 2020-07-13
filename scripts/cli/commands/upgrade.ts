import { ethers, constants, utils, Wallet } from 'ethers'

import { Argv } from 'yargs'

import { getAddressBook } from '../address-book'
import { readConfig, getContractConfig } from '../config'
import { cliOpts } from '../constants'
import { isContractDeployed, deployContract } from '../deploy'
import { getProvider } from '../utils'

const { EtherSymbol } = constants
const { formatEther } = utils

export const upgrade = async (
  wallet: Wallet,
  addressBookPath: string,
  graphConfigPath: string,
  force = false,
): Promise<void> => {
  // // Impl
  // const factory = await ethers.getContractFactory('Curation')
  // const contract = (await factory.connect(owner).deploy()) as Curation
  // // Proxy
  // const proxyFactory = await ethers.getContractFactory('GraphProxy')
  // const proxy = (await proxyFactory.connect(owner).deploy()) as GraphProxy
  // await proxy.connect(owner).upgradeTo(contract.address)
  // // Impl accept and initialize
  // await contract
  //   .connect(owner)
  //   .acceptUpgrade(
  //     proxy.address,
  //     graphToken,
  //     defaults.curation.reserveRatio,
  //     defaults.curation.minimumCurationStake,
  //   )
}

export const upgradeCommand = {
  command: 'upgrade',
  describe: 'Upgrade contract',
  builder: (yargs: Argv) => {
    return yargs.option('c', cliOpts.graphConfig)
  },
  handler: async (argv: { [key: string]: any } & Argv['argv']) => {
    await upgrade(
      Wallet.fromMnemonic(argv.mnemonic).connect(getProvider(argv.ethProvider)),
      argv.addressBook,
      argv.graphConfig,
      argv.force,
    )
  },
}
