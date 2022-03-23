import yargs, { Argv } from 'yargs'

import { logger } from '../../logging'
import { getContractAt } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'
import { ContractFunction } from 'ethers'

import { ProtocolFunction } from './index'

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
  // Epochs
  'epochs-length': { contract: 'EpochManager', name: 'epochLength' },
  'epochs-current': { contract: 'EpochManager', name: 'currentEpoch' },
  // Rewards
  'rewards-issuance-rate': { contract: 'RewardsManager', name: 'issuanceRate' },
  'subgraph-availability-oracle': {
    contract: 'RewardsManager',
    name: 'subgraphAvailabilityOracle',
  },
  // GNS
  'gns-bonding-curve': { contract: 'GNS', name: 'bondingCurve' },
  'gns-owner-tax-percentage': { contract: 'GNS', name: 'ownerTaxPercentage' },
  // Token
  'token-governor': { contract: 'GraphToken', name: 'governor' },
  'token-supply': { contract: 'GraphToken', name: 'totalSupply' },
  // Controller
  'controller-governor': { contract: 'Controller', name: 'governor' },
  'controller-get-contract-proxy': { contract: 'Controller', name: 'getContractProxy' },
  'controller-get-paused': { contract: 'Controller', name: 'paused' },
  'controller-get-partial-paused': { contract: 'Controller', name: 'partialPaused' },
  'controller-get-pause-guardian': { contract: 'Controller', name: 'pauseGuardian' },
  'l1-gateway-l2-grt': { contract: 'L1GraphTokenGateway', name: 'l2GRT' },
  'l1-gateway-inbox': { contract: 'L1GraphTokenGateway', name: 'inbox' },
  'l1-gateway-escrow': { contract: 'L1GraphTokenGateway', name: 'escrow' },
  'l1-gateway-l1-router': { contract: 'L1GraphTokenGateway', name: 'l1Router' },
  'l1-gateway-l2-counterpart': { contract: 'L1GraphTokenGateway', name: 'l2Counterpart' },
  'l1-gateway-paused': { contract: 'L1GraphTokenGateway', name: 'paused' },
  'l2-gateway-l1-grt': { contract: 'L2GraphTokenGateway', name: 'l1GRT' },
  'l2-gateway-l2-router': { contract: 'L2GraphTokenGateway', name: 'l2Router' },
  'l2-gateway-l1-counterpart': { contract: 'L2GraphTokenGateway', name: 'l1Counterpart' },
  'l2-gateway-paused': { contract: 'L2GraphTokenGateway', name: 'paused' },
  'l2-token-gateway': { contract: 'L2GraphToken', name: 'gateway' },
  'l2-token-l1-address': { contract: 'L2GraphToken', name: 'l1Address' },
}

const buildHelp = () => {
  let help = '$0 protocol get <fn> [params]\n\nGraph protocol configuration\n\nCommands:\n\n'
  for (const entry of Object.keys(gettersList)) {
    help += '  $0 protocol get ' + entry + ' [params]\n'
  }
  return help
}

export const getProtocolParam = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.info(`Getting ${cliArgs.fn}...`)

  const fn: ProtocolFunction = gettersList[cliArgs.fn]
  if (!fn) {
    logger.error(`Command ${cliArgs.fn} does not exist`)
    return
  }

  const addressEntry = cli.addressBook.getEntry(fn.contract)

  // Parse params
  const params = cliArgs.params ? cliArgs.params.toString().split(',') : []

  // Send tx
  const contract = getContractAt(fn.contract, addressEntry.address).connect(cli.wallet)
  const contractFn: ContractFunction = contract.functions[fn.name]

  const [value] = await contractFn(...params)
  logger.info(`${fn.name} = ${value}`)
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
