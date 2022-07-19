import yargs, { Argv } from 'yargs'
import { parseGRT } from '@graphprotocol/common-ts'

import { logger } from '../../logging'
import { sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'

export const stake = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const staking = cli.contracts.Staking

  logger.info(`Staking ${cliArgs.amount} tokens...`)
  await sendTransaction(cli.wallet, staking, 'stake', [amount])
}

export const unstake = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const amount = parseGRT(cliArgs.amount)
  const staking = cli.contracts.Staking

  logger.info(`Unstaking ${cliArgs.amount} tokens...`)
  await sendTransaction(cli.wallet, staking, 'unstake', [amount])
}

export const withdraw = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const staking = cli.contracts.Staking

  logger.info(`Withdrawing ${cliArgs.amount} tokens...`)
  await sendTransaction(cli.wallet, staking, 'withdraw')
}

export const allocate = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const subgraphDeploymentID = cliArgs.subgraphDeploymentID
  const amount = parseGRT(cliArgs.amount)
  const allocationID = cliArgs.allocationID
  const metadata = cliArgs.metadata
  const proof = cliArgs.proof
  const staking = cli.contracts.Staking

  logger.info(`Allocating ${cliArgs.amount} tokens on ${subgraphDeploymentID}...`)
  await sendTransaction(cli.wallet, staking, 'allocateFrom', [
    cli.walletAddress,
    subgraphDeploymentID,
    amount,
    allocationID,
    metadata,
    proof,
  ])
}

export const closeAllocation = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const allocationID = cliArgs.allocationID
  const poi = cliArgs.poi
  const staking = cli.contracts.Staking

  logger.info(`Closing allocation ${allocationID} with poi ${poi}...`)
  await sendTransaction(cli.wallet, staking, 'closeAllocation', [allocationID, poi])
}

export const claim = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const allocationID = cliArgs.allocationID
  const restake = cliArgs.restake
  const staking = cli.contracts.Staking

  logger.info(`Claiming allocation ${allocationID} with restake = ${restake}...`)
  await sendTransaction(cli.wallet, staking, 'claim', [allocationID, restake])
}

export const delegate = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const indexer = cliArgs.indexer
  const amount = parseGRT(cliArgs.amount)
  const staking = cli.contracts.Staking

  logger.info(`Delegating ${cliArgs.amount} tokens to indexer ${indexer}...`)
  await sendTransaction(cli.wallet, staking, 'delegate', [indexer, amount])
}

export const undelegate = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const indexer = cliArgs.indexer
  const amount = parseGRT(cliArgs.amount)
  const staking = cli.contracts.Staking

  logger.info(`Undelegating ${cliArgs.amount} tokens from indexer ${indexer}...`)
  await sendTransaction(cli.wallet, staking, 'undelegate', [indexer, amount])
}

export const withdrawDelegated = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const indexer = cliArgs.indexer
  const newIndexer = cliArgs.newIndexer
  const staking = cli.contracts.Staking

  if (newIndexer != '0x0000000000000000000000000000000000000000') {
    logger.info(`Withdrawing from ${indexer} to new indexer ${newIndexer}...`)
  } else {
    logger.info(`Withdrawing from ${indexer} without restaking`)
  }
  await sendTransaction(cli.wallet, staking, 'withdrawDelegated', [indexer, newIndexer])
}

export const setDelegationParameters = async (
  cli: CLIEnvironment,
  cliArgs: CLIArgs,
): Promise<void> => {
  const indexingRewardCut = cliArgs.indexingRewardCut
  const queryFeeCut = cliArgs.queryFeeCut
  const cooldownBlocks = cliArgs.cooldownBlocks
  const staking = cli.contracts.Staking

  logger.info(`Setting the following delegation parameters for indexer ${cli.walletAddress}
      indexingRewardCut = ${indexingRewardCut}
      queryFeeCut       = ${queryFeeCut}
      cooldownBlocks    = ${cooldownBlocks}
  `)
  await sendTransaction(cli.wallet, staking, 'setDelegationParameters', [
    indexingRewardCut,
    queryFeeCut,
    cooldownBlocks,
  ])
}
export const setOperator = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  const operator = cliArgs.operator
  const allowed = cliArgs.allowed
  const staking = cli.contracts.Staking
  logger.info(`Setting operator ${operator} to ${allowed} for account ${cli.walletAddress}`)
  await sendTransaction(cli.wallet, staking, 'setOperator', [operator, allowed])
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
            .option('allocationID', {
              description: 'Address used by the indexer as destination of funds of state channel',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('metadata', {
              description: 'IPFS hash of the metadata for the allocation',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('proof', {
              description:
                'A 65-bytes Ethereum signed message of `keccak256(indexerAddress,allocationID)`',
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
        command: 'close-allocation',
        describe: 'Close an allocation',
        builder: (yargs: Argv) => {
          return yargs
            .option('allocationID', {
              description: 'The allocation being closed',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('poi', {
              description: 'Proof of indexing',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return closeAllocation(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'claim',
        describe: 'Claim rebate',
        builder: (yargs: Argv) => {
          return yargs
            .option('allocationID', {
              description: 'The allocation claimed from the rebate pool',
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
      .command({
        command: 'setDelegationParameters',
        describe: 'Sets the delegation parameters for an indexer',
        builder: (yargs: Argv) => {
          return yargs
            .option('indexingRewardCut', {
              description: 'Percentage of indexing rewards left for delegators',
              type: 'number',
              requiresArg: true,
              demandOption: true,
            })
            .option('queryFeeCut', {
              description: 'Percentage of query fees left for delegators',
              type: 'number',
              requiresArg: true,
              demandOption: true,
            })
            .option('cooldownBlocks', {
              description: 'Period that need to pass to update delegation parameters',
              type: 'number',
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return setDelegationParameters(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'setOperator',
        describe: 'Set the operator for a graph account',
        builder: (yargs: Argv) => {
          return yargs
            .option('operator', {
              description: 'Address of the operator',
              type: 'string',
              requiresArg: true,
              demandOption: true,
            })
            .option('allowed', {
              description: 'Set to true to be an operator, false to revoke',
              type: 'boolean',
              requiresArg: true,
              demandOption: true,
            })
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return setOperator(await loadEnv(argv), argv)
        },
      })
  },
  handler: (): void => {
    yargs.showHelp()
  },
}
