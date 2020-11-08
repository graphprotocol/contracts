import consola from 'consola'
import yargs, { Argv } from 'yargs'

import { getContractAt } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { ContractFunction } from 'ethers'

import { ProtocolFunction } from './index'

const logger = consola.create({})

export const gettersList = {
  // Staking
  'staking-slasher': { contract: 'Staking', name: 'slashers' },
  'staking-thawing-period': { contract: 'Staking', name: 'thawingPeriod' },
  'staking-dispute-epochs': { contract: 'Staking', name: 'channelDisputeEpochs' },
  'staking-max-allocation-epochs': { contract: 'Staking', name: 'maxAllocationEpochs' },
  'staking-delegation-ratio': { contract: 'Staking', name: 'delegationRatio' },
  'staking-delegation-parameters-cooldown': {
    contract: 'Staking',
    name: 'delegationParametersCooldown',
  },
  'staking-delegation-unbonding-period': { contract: 'Staking', name: 'delegationUnbondingPeriod' },
  'protocol-percentage': { contract: 'Staking', name: 'protocolPercentage' },
  // Curation
  'curation-reserve-ratio': { contract: 'Curation', name: 'defaultReserveRatio' },
  'curation-percentage': { contract: 'Staking', name: 'curationPercentage' },
  'curation-minimum-deposit': { contract: 'Curation', name: 'minimumCurationDeposit' },
  'curation-tax-percentage': { contract: 'Curation', name: 'curationTaxPercentage' },
  'curation-bonding-curve': { contract: 'Curation', name: 'bondingCurve' },
  // Disputes
  'disputes-arbitrator': { contract: 'DisputeManager', name: 'arbitrator' },
  'disputes-minimum-deposit': { contract: 'DisputeManager', name: 'minimumDeposit' },
  'disputes-reward-percentage': { contract: 'DisputeManager', name: 'fishermanRewardPercentage' },
  'disputes-slashing-percentage': { contract: 'DisputeManager', name: 'slashingPercentage' },
  // Epochs
  'epochs-length': { contract: 'EpochManager', name: 'epochLength' },
  'epochs-current': { contract: 'EpochManager', name: 'currentEpoch' },
  // Rewards
  'rewards-issuance-rate': { contract: 'RewardsManager', name: 'issuanceRate' },
  // GNS
  'gns-bonding-curve': { contract: 'GNS', name: 'bondingCurve' },
  'gns-owner-fee-percentage': { contract: 'GNS', name: 'ownerFeePercentage' },
  // Token
  'token-governor': { contract: 'GraphToken', name: 'governor' },
  'token-supply': { contract: 'GraphToken', name: 'totalSupply' },
  // Controller
  'controller-governor': { contract: 'Controller', name: 'governor' },
  'controller-get-contract-proxy': { contract: 'Controller', name: 'getContractProxy' },
  'controller-get-paused': { contract: 'Controller', name: 'paused' },
  'controller-get-partial-paused': { contract: 'Controller', name: 'partialPaused' },
  'controller-get-pause-guardian': { contract: 'Controller', name: 'pauseGuardian' },
}

const buildHelp = () => {
  let help = '$0 protocol get <fn> [params]\n\nGraph protocol configuration\n\nCommands:\n\n'
  for (const entry of Object.keys(gettersList)) {
    help += '  $0 protocol get ' + entry + ' [params]\n'
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

export const getCommand = {
  command: 'get <fn> [params]',
  describe: 'Get network parameter',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs.usage(buildHelp())
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return getProtocolParam(await loadEnv(argv), argv)
  },
}
