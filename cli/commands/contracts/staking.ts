import consola from 'consola'
import yargs, { Argv } from 'yargs'
import { parseGRT } from '@graphprotocol/common-ts'

import { sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'

const logger = consola.create({})

export const stake = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const staking = cli.contracts.Staking

  logger.log(`Staking ${cliArgs.amount} tokens...`)
  await sendTransaction(cli.wallet, staking, 'stake', ...[amount])
}

export const unstake = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const staking = cli.contracts.Staking

  logger.log(`Unstaking ${cliArgs.amount} tokens...`)
  await sendTransaction(cli.wallet, staking, 'unstake', ...[amount])
}

export const withdraw = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const staking = cli.contracts.Staking

  logger.log(`Withdrawing ${cliArgs.amount} tokens...`)
  await sendTransaction(cli.wallet, staking, 'withdraw')
}

export const allocate = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const subgraphDeploymentID = cliArgs.subgraphDeploymentID
  const amount = parseGRT(cliArgs.amount)
  const channelPubKey = cliArgs.channelPubKey
  const channelProxy = cliArgs.channelProxy
  const price = cliArgs.price
  const staking = cli.contracts.Staking

  logger.log(`Allocating ${cliArgs.amount} tokens on ${subgraphDeploymentID}...`)
  await sendTransaction(
    cli.wallet,
    staking,
    'allocate',
    ...[subgraphDeploymentID, amount, channelPubKey, channelProxy, price],
  )
}

export const settle = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const channelID = cliArgs.channelID
  const staking = cli.contracts.Staking

  logger.log(`Settling allocation with channelID ${channelID}...`)
  await sendTransaction(cli.wallet, staking, 'settle', ...[channelID])
}

export const collect = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.log(
    `COLLECT NOT IMPLEMENTED. NORMALLY CALLED FROM PROXY ACCOUNT. plan is to 
     implement this in the near future when we start adding some more 
     functionality to the CLI and supporting scripts`,
  )
}

export const claim = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const channelID = cliArgs.channelID
  const restake = cliArgs.restake
  const staking = cli.contracts.Staking

  logger.log(`Claiming on ${channelID} with restake = ${restake}...`)
  await sendTransaction(cli.wallet, staking, 'claim', ...[channelID, restake])
}

export const delegate = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const indexer = cliArgs.indexer
  const amount = parseGRT(cliArgs.amount)
  const staking = cli.contracts.Staking

  logger.log(`Delegating ${cliArgs.amount} tokens to indexer ${indexer}...`)
  await sendTransaction(cli.wallet, staking, 'delegate', ...[indexer, amount])
}

export const undelegate = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const indexer = cliArgs.indexer
  const amount = parseGRT(cliArgs.amount)
  const staking = cli.contracts.Staking

  logger.log(`Undelegating ${cliArgs.amount} tokens from indexer ${indexer}...`)
  await sendTransaction(cli.wallet, staking, 'undelegate', ...[indexer, amount])
}

export const withdrawDelegated = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const indexer = cliArgs.indexer
  const newIndexer = cliArgs.newIndexer
  const staking = cli.contracts.Staking

  if (newIndexer != '0x0000000000000000000000000000000000000000') {
    logger.log(`Withdrawing from ${indexer} to new indexer ${newIndexer}...`)
  } else {
    logger.log(`Withdrawing from ${indexer} without restaking`)
  }
  await sendTransaction(cli.wallet, staking, 'withdrawDelegated', ...[indexer, newIndexer])
}

export const stakingCommand = {
  command: 'staking',
  describe: 'Staking contract calls',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .command({
        command: 'stake',
        describe: 'Stake GRT',
        builder: (yargs: Argv) => {
          return yargs.option('amount', {
            description: 'Amount of tokens to stake. CLI converts to a BN with 10^18',
            type: 'string',
            requiresArg: true,
            demandOption: true,
          })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return stake(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'unstake',
        describe: 'Unstake GRT',
        builder: (yargs: Argv) => {
          return yargs.option('amount', {
            description: 'Amount of tokens to unstake. CLI converts to a BN with 10^18',
            type: 'string',
            requiresArg: true,
            demandOption: true,
          })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return unstake(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'withdraw',
        describe: 'Withdraw unlocked GRT',
        handler: async (argv: CLIArgs): Promise<void> => {
          return withdraw(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'allocate',
        describe: 'Allocate GRT on a subgraph deployment',
        builder: (yargs: Argv) => {
          return yargs
            .option('subgraphDeploymentID', {
              description: 'The subgraph deployment ID being allocated on',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('amount', {
              description: 'Amount of tokens being allocated. CLI converts to a BN with 10^18',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('channelPubKey', {
              description: 'The public key used by the indexer to setup the off-chain channel',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('channelProxy', {
              description: 'Address of the multisig proxy used to hold channel funds',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('price', {
              description: 'Price the indexer will charge for serving queries of the subgraphID',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return allocate(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'settle',
        describe: 'Settle an allocation',
        builder: (yargs: Argv) => {
          return yargs.option('channelID', {
            description: 'The channel / allocation being settled',
            type: 'string',
            requiresArg: true,
            demandOption: true,
          })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return settle(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'collect',
        describe: 'Channel proxy calls this to collect GRT',
        builder: (yargs: Argv) => {
          return yargs
            .option('channelID', {
              description: 'ID of the channel we are collecting funds from',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('amount', {
              description: 'Token amount to withdraw',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('from', {
              description: 'Multisig channel address that triggered the withdrawal',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return collect(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'claim',
        describe: 'Claim GRT',
        builder: (yargs: Argv) => {
          return yargs
            .option('channelID', {
              description: 'ID of the channel we are claiming funds from',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('restake', {
              description: 'True if you are restaking the fees, rather than withdrawing',
              type: 'boolean',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return claim(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'delegate',
        describe: 'Delegate GRT',
        builder: (yargs: Argv) => {
          return yargs
            .option('indexer', {
              description: 'Indexer being delegated to',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('amount', {
              description: 'Amount of tokens. CLI converts to a BN with 10^18',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return delegate(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'undelegate',
        describe: 'Undelegate GRT',
        builder: (yargs: Argv) => {
          return yargs
            .option('indexer', {
              description: 'Indexer being undelegated on',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('amount', {
              description: 'Amount of tokens. CLI converts to a BN with 10^18',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return undelegate(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'withdrawDelegated',
        describe: 'Withdrawn unlocked delegated GRT',
        builder: (yargs: Argv) => {
          return yargs
            .option('indexer', {
              description: 'Indexer being withdrawn from to',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('newIndexer', {
              description:
                'New indexer being delegated to. if address(0) it will return the tokens',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return withdrawDelegated(await loadEnv(argv), argv)
        },
      })
  },
  handler: (): void => {
    yargs.showHelp()
  },
}
