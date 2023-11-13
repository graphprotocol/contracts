import yargs, { Argv } from 'yargs'
import { utils } from 'ethers'

import { sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { logger } from '../../logging'

export const registerTestName = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const name = cliArgs.name
  // eslint-disable-next-line  @typescript-eslint/no-explicit-any
  const testRegistrar = (cli.contracts as any).ITestRegistrar
  const normalizedName = name.toLowerCase()
  const labelNameFull = `${normalizedName}.${'eth'}`
  const labelHashFull = utils.namehash(labelNameFull)
  const label = utils.keccak256(utils.toUtf8Bytes(normalizedName))
  logger.info(`Namehash for ${labelNameFull}: ${labelHashFull}`)
  logger.info(`Registering ${name} with ${cli.walletAddress} on the test registrar`)
  await sendTransaction(cli.wallet, testRegistrar, 'register', [label, cli.walletAddress])
}
export const checkOwner = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const name = cliArgs.name
  const ens = cli.contracts.IENS
  const node = nameToNode(name)
  const res = await ens.owner(node)
  logger.info(`owner = ${res}`)
}

export const nameToNode = (name: string): string => {
  const node = utils.namehash(`${name}.eth`)
  logger.info(`Name: ${name}`)
  logger.info(`Node: ${node}`)
  return node
}

export const ensCommand = {
  command: 'ens',
  describe: 'ENS contract calls',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .command({
        command: 'registerTestName',
        describe: 'Register a name on the test registrar',
        builder: (yargs: Argv) => {
          return yargs.option('name', {
            description: 'Name being registered',
            type: 'string',
            requiresArg: true,
            demandOption: true,
          })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return registerTestName(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'checkOwner',
        describe: 'Check the owner of a name',
        builder: (yargs: Argv) => {
          return yargs.option('name', {
            description: 'Name being checked',
            type: 'string',
            requiresArg: true,
            demandOption: true,
          })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return checkOwner(await loadEnv(argv), argv)
        },
      })
  },
  handler: (): void => {
    yargs.showHelp()
  },
}
