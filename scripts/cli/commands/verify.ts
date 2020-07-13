import { Wallet } from 'ethers'
import consola from 'consola'
import { Argv } from 'yargs'

import { getAddressBook } from '../address-book'
import { getProvider } from '../utils'
import { execSync } from 'child_process'

const coreContracts = [
  'EpochManager',
  'GNS',
  'GraphToken',
  'ServiceRegistry',
  'Curation',
  'RewardsManager',
  'Staking',
  'DisputeManager',
  'IndexerCTDT',
  'IndexerSingleAssetInterpreter',
  'IndexerMultiAssetInterpreter',
  'IndexerWithdrawInterpreter',
  'MinimumViableMultisig',
]

const logger = consola.create({})

export const verify = async (wallet: Wallet, addressBookPath: string): Promise<void> => {
  const chainId = (await wallet.provider.getNetwork()).chainId
  const addressBook = getAddressBook(addressBookPath, chainId.toString())
  logger.log(
    `* Verifying contracts for chainId (${chainId}) using address-book (${addressBookPath})`,
  )

  for (const contractName of coreContracts) {
    const contract = addressBook.getEntry(contractName)
    if (!contract) {
      logger.log(
        `- ERROR: Contract ${contractName} not found in address-book for network ${chainId}`,
      )
      continue
    }

    const address = contract.address
    const args = contract.constructorArgs ? contract.constructorArgs.map((e) => e.value) : []
    const argsList = args.map((e) => `"${e}"`).join(' ')
    const cmd = `buidler verify-contract --contract-name ${contractName} --address ${address} ${argsList}`

    try {
      logger.log(`> Verifying contract ${contractName}::${address} ...`)
      await execSync(cmd)
      logger.log(`+ Contract ${contractName}::${address} verified`)
    } catch (err) {
      logger.log(`- ERROR: ${contractName}::${address}`)
    }
  }
}

export const verifyCommand = {
  command: 'verify',
  describe: 'Verify contracts',
  handler: async (argv: { [key: string]: any } & Argv['argv']) => {
    await verify(
      Wallet.fromMnemonic(argv.mnemonic).connect(getProvider(argv.ethProvider)),
      argv.addressBook,
    )
  },
}
