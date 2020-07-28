import consola from 'consola'
import { execSync } from 'child_process'

import { loadEnv, CLIArgs, CLIEnvironment } from '../env'

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

export const verify = async (cli: CLIEnvironment): Promise<void> => {
  logger.log(`Verifying contracts for chainId ${cli.chainId}...`)

  for (const contractName of coreContracts) {
    const contract = cli.addressBook.getEntry(contractName)
    if (!contract) {
      logger.log(
        `- ERROR: Contract ${contractName} not found in address-book for network ${cli.chainId}`,
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
  handler: async (argv: CLIArgs): Promise<void> => {
    return verify(await loadEnv(argv))
  },
}
