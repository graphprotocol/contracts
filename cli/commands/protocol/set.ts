import consola from 'consola'
import yargs, { Argv } from 'yargs'

import { getContractAt, sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'

import { ProtocolFunction } from './index'

const logger = consola.create({})

export const settersList = {
  // Staking
  'staking-governor': { contract: 'Staking', name: 'setGovernor' },
  'staking-slasher': { contract: 'Staking', name: 'setSlasher' },
  'staking-curation-contract': { contract: 'Staking', name: 'setCuration' },
  'staking-rewards-contract': { contract: 'Staking', name: 'setRewardsManager' },
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
  // Curation
  'curation-governor': { contract: 'Curation', name: 'setGovernor' },
  'curation-staking-contract': { contract: 'Curation', name: 'setStaking' },
  'curation-rewards-contract': { contract: 'Curation', name: 'setRewardsManager' },
  'curation-reserve-ratio': { contract: 'Curation', name: 'setDefaultReserveRatio' },
  'curation-percentage': { contract: 'Staking', name: 'setCurationPercentage' },
  'curation-minimum-deposit': { contract: 'Curation', name: 'setMinimumCurationDeposit' },
  'curation-withdrawal-percentage': { contract: 'Curation', name: 'setWithdrawalFeePercentage' },
  // Disputes
  'disputes-governor': { contract: 'DisputeManager', name: 'setGovernor' },
  'disputes-arbitrator': { contract: 'DisputeManager', name: 'setArbitrator' },
  'disputes-minimum-deposit': { contract: 'DisputeManager', name: 'setMinimumDeposit' },
  'disputes-reward-percentage': {
    contract: 'DisputeManager',
    name: 'setFishermanRewardPercentage',
  },
  'disputes-slashing-percentage': { contract: 'DisputeManager', name: 'setSlashingPercentage' },
  'disputes-staking': { contract: 'DisputeManager', name: 'setStaking' },
  // Epochs
  'epochs-governor': { contract: 'EpochManager', name: 'setGovernor' },
  'epochs-length': { contract: 'EpochManager', name: 'setEpochLength' },
  // Rewards
  'rewards-issuance-rate': { contract: 'RewardsManager', name: 'setIssuanceRate' },
  // GNS
  'gns-minimum-signal': { contract: 'GNS', name: 'setMinimumVsignal' },
  // Token
  'token-governor': { contract: 'GraphToken', name: 'setGovernor' },
  'token-add-minter': { contract: 'GraphToken', name: 'addMinter' },
  'token-remove-minter': { contract: 'GraphToken', name: 'removeMinter' },
  'token-mint': { contract: 'GraphToken', name: 'mint' },
}

const buildHelp = () => {
  let help = '$0 protocol set <fn> <params>\n\nGraph protocol configuration\n\nCommands:\n\n'
  for (const entry of Object.keys(settersList)) {
    help += '  $0 protocol set ' + entry + ' <params>\n'
  }
  return help
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

export const setCommand = {
  command: 'set <fn> <params>',
  describe: 'Set protocol parameter',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs.usage(buildHelp())
  },
  handler: async (argv: CLIArgs): Promise<void> => {
    return setProtocolParam(await loadEnv(argv), argv)
  },
}
