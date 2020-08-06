import Table from 'cli-table'
import consola from 'consola'
import yargs, { Argv } from 'yargs'

import { getContractAt, sendTransaction } from '../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../env'
import { ContractFunction } from 'ethers'

const logger = consola.create({})

interface ProtocolFunction {
  contract: string
  name: string
}

const contractNames = ['GraphToken', 'EpochManager', 'Staking', 'Curation', 'DisputeManager']

const gettersList = {
  'staking-governor': { contract: 'Staking', name: 'governor' },
  'staking-slasher': { contract: 'Staking', name: 'slashers' },
  'staking-curation-contract': { contract: 'Staking', name: 'curation' },
  'staking-thawing-period': { contract: 'Staking', name: 'thawingPeriod' },
  'staking-dispute-epochs': { contract: 'Staking', name: 'channelDisputeEpochs' },
  'staking-max-allocation-epochs': { contract: 'Staking', name: 'maxAllocationEpochs' },
  'staking-delegation-capacity': { contract: 'Staking', name: 'delegationCapacity' },
  'staking-delegation-parameters-cooldown': {
    contract: 'Staking',
    name: 'delegationParametersCooldown',
  },
  'staking-delegation-unbonding-period': { contract: 'Staking', name: 'delegationUnbondingPeriod' },
  'protocol-percentage': { contract: 'Staking', name: 'protocolPercentage' },
  'curation-governor': { contract: 'Curation', name: 'governor' },
  'curation-staking-contract': { contract: 'Curation', name: 'staking' },
  'curation-reserve-ratio': { contract: 'Curation', name: 'defaultReserveRatio' },
  'curation-percentage': { contract: 'Staking', name: 'curationPercentage' },
  'curation-minimum-deposit': { contract: 'Curation', name: 'minimumCurationDeposit' },
  'curation-withdrawal-percentage': { contract: 'Curation', name: 'withdrawalFeePercentage' },
  'disputes-governor': { contract: 'DisputeManager', name: 'governor' },
  'disputes-arbitrator': { contract: 'DisputeManager', name: 'arbitrator' },
  'disputes-minimum-deposit': { contract: 'DisputeManager', name: 'minimumDeposit' },
  'disputes-reward-percentage': { contract: 'DisputeManager', name: 'fishermanRewardPercentage' },
  'disputes-slashing-percentage': { contract: 'DisputeManager', name: 'slashingPercentage' },
  'disputes-staking': { contract: 'DisputeManager', name: 'staking' },
  'epochs-governor': { contract: 'EpochManager', name: 'governor' },
  'epochs-length': { contract: 'EpochManager', name: 'epochLength' },
  'epochs-current': { contract: 'EpochManager', name: 'currentEpoch' },
  'token-governor': { contract: 'GraphToken', name: 'governor' },
  'token-supply': { contract: 'GraphToken', name: 'totalSupply' },
  'token-minter': { contract: 'GraphToken', name: 'isMinter' },
}

const settersList = {
  'staking-governor': { contract: 'Staking', name: 'setGovernor' },
  'staking-slasher': { contract: 'Staking', name: 'setSlasher' },
  'staking-curation-contract': { contract: 'Staking', name: 'setCuration' },
  'staking-thawing-period': { contract: 'Staking', name: 'setThawingPeriod' },
  'staking-dispute-epochs': { contract: 'Staking', name: 'setChannelDisputeEpochs' },
  'staking-max-allocation-epochs': { contract: 'Staking', name: 'setMaxAllocationEpochs' },
  'staking-protocol-percentage': { contract: 'Staking', name: 'setProtocolPercentage' },
  'staking-delegation-capacity': { contract: 'Staking', name: 'setDelegationCapacity' },
  'staking-delegation-parameters-cooldown': {
    contract: 'Staking',
    name: 'setDelegationParametersCooldown',
  },
  'staking-delegation-unbonding-period': {
    contract: 'Staking',
    name: 'setDelegationUnbondingPeriod',
  },
  'curation-governor': { contract: 'Curation', name: 'setGovernor' },
  'curation-staking-contract': { contract: 'Curation', name: 'setStaking' },
  'curation-reserve-ratio': { contract: 'Curation', name: 'setDefaultReserveRatio' },
  'curation-percentage': { contract: 'Staking', name: 'setCurationPercentage' },
  'curation-minimum-deposit': { contract: 'Curation', name: 'setMinimumCurationDeposit' },
  'curation-withdrawal-percentage': { contract: 'Curation', name: 'setWithdrawalFeePercentage' },
  'disputes-governor': { contract: 'DisputeManager', name: 'setGovernor' },
  'disputes-arbitrator': { contract: 'DisputeManager', name: 'setArbitrator' },
  'disputes-minimum-deposit': { contract: 'DisputeManager', name: 'setMinimumDeposit' },
  'disputes-reward-percentage': {
    contract: 'DisputeManager',
    name: 'setFishermanRewardPercentage',
  },
  'disputes-slashing-percentage': { contract: 'DisputeManager', name: 'setSlashingPercentage' },
  'disputes-staking': { contract: 'DisputeManager', name: 'setStaking' },
  'epochs-governor': { contract: 'EpochManager', name: 'setGovernor' },
  'epochs-length': { contract: 'EpochManager', name: 'setEpochLength' },
  'token-governor': { contract: 'GraphToken', name: 'setGovernor' },
  'token-add-minter': { contract: 'GraphToken', name: 'addMinter' },
  'token-remove-minter': { contract: 'GraphToken', name: 'removeMinter' },
  'token-mint': { contract: 'GraphToken', name: 'mint' },
}

// TODO: print help with fn signature
// TODO: list address-book
// TODO: add gas price

const buildGetProtocolHelp = () => {
  let help = '$0 protocol get <fn> [params]\n\nGraph protocol configuration\n\nCommands:\n\n'
  for (const entry of Object.keys(gettersList)) {
    help += '  $0 protocol get ' + entry + ' [params]\n'
  }
  return help
}

const buildSetProtocolHelp = () => {
  let help = '$0 protocol set <fn> <params>\n\nGraph protocol configuration\n\nCommands:\n\n'
  for (const entry of Object.keys(settersList)) {
    help += '  $0 protocol set ' + entry + ' <params>\n'
  }
  return help
}

export const getProtocolParam = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.log(`Getting ${cliArgs.fn}...`)

  const fn: ProtocolFunction = gettersList[cliArgs.fn]
  if (!fn) {
    consola.error(`Command ${cliArgs.fn} does not exist`)
    return
  }

  const addressEntry = cli.addressBook.getEntry(fn.contract)

  // Parse params
  const params = cliArgs.params ? cliArgs.params.toString().split(',') : []

  // Send tx
  const contract = getContractAt(fn.contract, addressEntry.address).connect(cli.wallet)
  const contractFn: ContractFunction = contract.functions[fn.name]

  const [value] = await contractFn(...params)
  logger.success(`${fn.name} = ${value}`)
}

export const setProtocolParam = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.log(`Setting ${cliArgs.fn}...`)

  const fn: ProtocolFunction = settersList[cliArgs.fn]
  if (!fn) {
    consola.error(`Command ${cliArgs.fn} does not exist`)
    return
  }

  const addressEntry = cli.addressBook.getEntry(fn.contract)

  // Parse params
  const params = cliArgs.params.toString().split(',')

  // Send tx
  const contract = getContractAt(fn.contract, addressEntry.address).connect(cli.wallet)
  await sendTransaction(cli.wallet, contract, fn.name, ...params)
}

export const listProtocolParams = async (cli: CLIEnvironment): Promise<void> => {
  logger.log(`>>> Protocol configuration <<<\n`)

  for (const contractName of contractNames) {
    const table = new Table({
      head: [contractName, 'Value'],
      colWidths: [30, 50],
    })

    const addressEntry = cli.addressBook.getEntry(contractName)
    const contract = getContractAt(contractName, addressEntry.address).connect(cli.wallet)
    table.push(['* address', contract.address])

    for (const fn of Object.values(gettersList)) {
      if (fn.contract != contractName) continue

      const addressEntry = cli.addressBook.getEntry(fn.contract)
      const contract = getContractAt(fn.contract, addressEntry.address).connect(cli.wallet)
      if (contract.interface.getFunction(fn.name).inputs.length == 0) {
        const contractFn: ContractFunction = contract.functions[fn.name]
        let [value] = await contractFn()
        if (typeof value === 'object') {
          value = value.toString()
        }
        table.push([fn.name, value])
      }
    }

    logger.log(table.toString())
  }
}

export const protocolCommand = {
  command: 'protocol',
  describe: 'Graph protocol configuration',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .command({
        command: 'get <fn> [params]',
        describe: 'Get network parameter',
        builder: (yargs: Argv) => {
          return yargs.usage(buildGetProtocolHelp())
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return getProtocolParam(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'set <fn> <params>',
        describe: 'Set network parameter',
        builder: (yargs: Argv) => {
          return yargs.usage(buildSetProtocolHelp())
        },
        handler: async (argv: CLIArgs): Promise<void> => {
          return setProtocolParam(await loadEnv(argv), argv)
        },
      })
      .command({
        command: 'list',
        describe: 'List network parameters',
        handler: async (argv: CLIArgs): Promise<void> => {
          return listProtocolParams(await loadEnv(argv))
        },
      })
  },
  handler: (argv: CLIArgs): void => {
    yargs.showHelp()
  },
}
