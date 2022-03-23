import yargs, { Argv } from 'yargs'

import { logger } from '../../logging'
import { getContractAt, sendTransaction } from '../../network'
import { loadEnv, CLIArgs, CLIEnvironment } from '../../env'

import { ProtocolFunction } from './index'
import { BigNumber } from 'ethers'

export const settersList = {
  // Staking
  'staking-slasher': { contract: 'Staking', name: 'setSlasher' },
  'staking-thawing-period': { contract: 'Staking', name: 'setThawingPeriod' },
  'staking-dispute-epochs': { contract: 'Staking', name: 'setChannelDisputeEpochs' },
  'staking-max-allocation-epochs': { contract: 'Staking', name: 'setMaxAllocationEpochs' },
  'staking-protocol-percentage': { contract: 'Staking', name: 'setProtocolPercentage' },
  'staking-delegation-ratio': { contract: 'Staking', name: 'setDelegationRatio' },
  'staking-delegation-parameters-cooldown': {
    contract: 'Staking',
    name: 'setDelegationParametersCooldown',
  },
  'staking-delegation-unbonding-period': {
    contract: 'Staking',
    name: 'setDelegationUnbondingPeriod',
  },
  // Curation
  'curation-reserve-ratio': { contract: 'Curation', name: 'setDefaultReserveRatio' },
  'curation-percentage': { contract: 'Staking', name: 'setCurationPercentage' },
  'curation-minimum-deposit': { contract: 'Curation', name: 'setMinimumCurationDeposit' },
  'curation-tax-percentage': { contract: 'Curation', name: 'setCurationTaxPercentage' },
  // Disputes
  'disputes-arbitrator': { contract: 'DisputeManager', name: 'setArbitrator' },
  'disputes-minimum-deposit': { contract: 'DisputeManager', name: 'setMinimumDeposit' },
  'disputes-reward-percentage': {
    contract: 'DisputeManager',
    name: 'setFishermanRewardPercentage',
  },
  'disputes-slashing-percentage': { contract: 'DisputeManager', name: 'setSlashingPercentage' },
  // Epochs
  'epochs-length': { contract: 'EpochManager', name: 'setEpochLength' },
  // Rewards
  'rewards-issuance-rate': { contract: 'RewardsManager', name: 'setIssuanceRate' },
  'subgraph-availability-oracle': {
    contract: 'RewardsManager',
    name: 'setSubgraphAvailabilityOracle',
  },
  // GNS
  'gns-owner-tax-percentage': { contract: 'GNS', name: 'setOwnerTaxPercentage' },
  // Token
  'token-transfer-governor': { contract: 'GraphToken', name: 'transferOwnership' },
  'token-accept-governor': { contract: 'GraphToken', name: 'acceptOwnership' },
  'token-add-minter': { contract: 'GraphToken', name: 'addMinter' },
  'token-remove-minter': { contract: 'GraphToken', name: 'removeMinter' },
  'token-mint': { contract: 'GraphToken', name: 'mint' },
  // Controller
  'controller-transfer-governor': { contract: 'Controller', name: 'transferOwnership' },
  'controller-accept-governor': { contract: 'Controller', name: 'acceptOwnership' },
  'controller-set-contract-proxy': { contract: 'Controller', name: 'setContractProxy' },
  'controller-set-paused': { contract: 'Controller', name: 'setPaused' },
  'controller-set-partial-paused': { contract: 'Controller', name: 'setPartialPaused' },
  'controller-set-pause-guardian': { contract: 'Controller', name: 'setPauseGuardian' },
  'l1-gateway-set-l2-grt': { contract: 'L1GraphTokenGateway', name: 'setL2TokenAddress' },
  'l1-gateway-set-arbitrum-addresses': {
    contract: 'L1GraphTokenGateway',
    name: 'setArbitrumAddresses',
  },
  'l1-gateway-set-l2-counterpart': {
    contract: 'L1GraphTokenGateway',
    name: 'setL2CounterpartAddress',
  },
  'l1-gateway-set-escrow-address': {
    contract: 'L1GraphTokenGateway',
    name: 'setEscrowAddress',
  },
  'l1-gateway-set-paused': { contract: 'L1GraphTokenGateway', name: 'setPaused' },
  'bridge-escrow-approve-all': { contract: 'BridgeEscrow', name: 'approveAll' },
  'bridge-escrow-revoke-all': { contract: 'BridgeEscrow', name: 'revokeAll' },
  'l2-gateway-set-l1-grt': { contract: 'L2GraphTokenGateway', name: 'setL1TokenAddress' },
  'l2-gateway-set-l2-router': { contract: 'L2GraphTokenGateway', name: 'setL2Router' },
  'l2-gateway-set-l1-counterpart': {
    contract: 'L2GraphTokenGateway',
    name: 'setL1CounterpartAddress',
  },
  'l2-gateway-set-paused': { contract: 'L2GraphTokenGateway', name: 'setPaused' },
  'l2-token-set-gateway': { contract: 'L2GraphToken', name: 'setGateway' },
  'l2-token-set-l1-address': { contract: 'L2GraphToken', name: 'setL1Address' },
}

const buildHelp = () => {
  let help = '$0 protocol set <fn> <params>\n\nGraph protocol configuration\n\nCommands:\n\n'
  for (const entry of Object.keys(settersList)) {
    help += '  $0 protocol set ' + entry + ' <params>\n'
  }
  return help
}

export const setProtocolParam = async (cli: CLIEnvironment, cliArgs: CLIArgs): Promise<void> => {
  logger.info(`Setting ${cliArgs.fn}...`)

  const fn: ProtocolFunction = settersList[cliArgs.fn]
  if (!fn) {
    logger.error(`Command ${cliArgs.fn} does not exist`)
    return
  }

  const addressEntry = cli.addressBook.getEntry(fn.contract)

  // Parse params
  const params = cliArgs.params.toString().split(',')
  const parsedParams = []
  for (const param of params) {
    try {
      const parsedParam = BigNumber.from(param)
      parsedParams.push(parsedParam.toNumber())
    } catch {
      parsedParams.push(param)
    }
  }
  logger.info(`params: ${parsedParams}`)

  // Send tx
  const contract = getContractAt(fn.contract, addressEntry.address).connect(cli.wallet)
  await sendTransaction(cli.wallet, contract, fn.name, parsedParams)
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
