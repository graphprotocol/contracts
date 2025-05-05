import YAML from 'yaml'
import { getItemValue, updateItemValue } from '../../lib/config'

import type { GraphNetworkContractName } from './contracts/list'
import type { GraphNetworkContracts } from './contracts/load'
import { toBN, toGRT } from '../../../utils'

interface GeneralParam {
  contract: GraphNetworkContractName // contract where the param is defined
  name: string // name of the parameter
}

interface Contract {
  name: string
  initParams: ContractInitParam[]
}

interface ContractInitParam {
  name: string // as declared in config.yml
  type: 'number' | 'BigNumber' // as returned by the contract
  getter?: string // name of function to get the value from the contract. Defaults to 'name'
  format?: 'number' // some parameters are stored in different formats than what the contract reports.
}

const epochManager: Contract = {
  name: 'EpochManager',
  initParams: [
    { name: 'lengthInBlocks', type: 'BigNumber', getter: 'epochLength', format: 'number' },
  ],
}

const curation: Contract = {
  name: 'Curation',
  initParams: [
    { name: 'reserveRatio', type: 'number', getter: 'defaultReserveRatio' },
    { name: 'curationTaxPercentage', type: 'number' },
    { name: 'minimumCurationDeposit', type: 'BigNumber' },
  ],
}

const disputeManager: Contract = {
  name: 'DisputeManager',
  initParams: [
    { name: 'minimumDeposit', type: 'BigNumber' },
    { name: 'fishermanRewardPercentage', type: 'number' },
    { name: 'idxSlashingPercentage', type: 'number' },
    { name: 'qrySlashingPercentage', type: 'number' },
  ],
}

const staking: Contract = {
  name: 'Staking',
  initParams: [
    { name: 'minimumIndexerStake', type: 'BigNumber' },
    { name: 'thawingPeriod', type: 'number' },
    { name: 'protocolPercentage', type: 'number' },
    { name: 'curationPercentage', type: 'number' },
    { name: 'maxAllocationEpochs', type: 'number' },
    { name: 'delegationUnbondingPeriod', type: 'number' },
    { name: 'delegationRatio', type: 'number' },
    { name: 'rebateAlphaNumerator', type: 'number', getter: 'alphaNumerator' },
    { name: 'rebateAlphaDenominator', type: 'number', getter: 'alphaDenominator' },
    { name: 'rebateLambdaNumerator', type: 'number', getter: 'lambdaNumerator' },
    { name: 'rebateLambdaDenominator', type: 'number', getter: 'lambdaDenominator' },
  ],
}

const rewardsManager: Contract = {
  name: 'RewardsManager',
  initParams: [{ name: 'issuancePerBlock', type: 'BigNumber' }],
}

export const GraphNetworkConfigContractList: Contract[] = [
  epochManager,
  curation,
  disputeManager,
  staking,
  rewardsManager,
]

export const GraphNetworkConfigGeneralParams: GeneralParam[] = [
  {
    contract: 'DisputeManager',
    name: 'arbitrator',
  },
  {
    contract: 'Controller',
    name: 'governor',
  },
  {
    contract: 'AllocationExchange',
    name: 'authority',
  },
]

export const updateGeneralParams = async (
  contracts: GraphNetworkContracts,
  param: GeneralParam,
  config: YAML.Document.Parsed,
) => {
  // TODO: can we fix this?
  // eslint-disable-next-line @typescript-eslint/ban-ts-comment
  // @ts-ignore
  const value = await contracts[param.contract][param.name]()
  const updated = updateItemValue(config, `general/${param.name}`, value)
  if (updated) {
    console.log(`\t- Updated ${param.name} to ${value}`)
  }
}

export const updateContractParams = async (
  contracts: GraphNetworkContracts,
  contract: Contract,
  config: YAML.Document.Parsed,
) => {
  for (const param of contract.initParams) {
    // TODO: can we fix this?
    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
    // @ts-ignore
    let value = await contracts[contract.name][param.getter ?? param.name]()
    if (param.type === 'BigNumber') {
      if (param.format === 'number') {
        value = value.toNumber()
      } else {
        value = value.toString()
      }
    }

    const updated = updateItemValue(config, `contracts/${contract.name}/init/${param.name}`, value)
    if (updated) {
      console.log(`\t- Updated ${param.name} to ${value}`)
    }
  }
}

export const getDefaults = (config: YAML.Document.Parsed, isL1: boolean) => {
  const staking = isL1 ? 'L1Staking' : 'L2Staking'
  return {
    curation: {
      reserveRatio: getItemValue(config, 'contracts/Curation/init/reserveRatio'),
      minimumCurationDeposit: getItemValue(
        config,
        'contracts/Curation/init/minimumCurationDeposit',
      ),
      l2MinimumCurationDeposit: toBN(1),
      curationTaxPercentage: getItemValue(config, 'contracts/Curation/init/curationTaxPercentage'),
    },
    dispute: {
      minimumDeposit: getItemValue(config, 'contracts/DisputeManager/init/minimumDeposit'),
      fishermanRewardPercentage: getItemValue(
        config,
        'contracts/DisputeManager/init/fishermanRewardPercentage',
      ),
      qrySlashingPercentage: getItemValue(
        config,
        'contracts/DisputeManager/init/qrySlashingPercentage',
      ),
      idxSlashingPercentage: getItemValue(
        config,
        'contracts/DisputeManager/init/idxSlashingPercentage',
      ),
    },
    epochs: {
      lengthInBlocks: getItemValue(config, 'contracts/EpochManager/init/lengthInBlocks'),
    },
    staking: {
      minimumIndexerStake: getItemValue(config, `contracts/${staking}/init/minimumIndexerStake`),
      maxAllocationEpochs: getItemValue(config, `contracts/${staking}/init/maxAllocationEpochs`),
      thawingPeriod: getItemValue(config, `contracts/${staking}/init/thawingPeriod`),
      delegationUnbondingPeriod: getItemValue(
        config,
        `contracts/${staking}/init/delegationUnbondingPeriod`,
      ),
      alphaNumerator: getItemValue(
        config,
        `contracts/${staking}/init/rebateParameters/alphaNumerator`,
      ),
      alphaDenominator: getItemValue(
        config,
        `contracts/${staking}/init/rebateParameters/alphaDenominator`,
      ),
      lambdaNumerator: getItemValue(
        config,
        `contracts/${staking}/init/rebateParameters/lambdaNumerator`,
      ),
      lambdaDenominator: getItemValue(
        config,
        `contracts/${staking}/init/rebateParameters/lambdaDenominator`,
      ),
    },
    token: {
      initialSupply: getItemValue(config, 'contracts/GraphToken/init/initialSupply'),
    },
    rewards: {
      issuancePerBlock: '114155251141552511415',
    },
  }
}
