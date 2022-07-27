import { task } from 'hardhat/config'
import { cliOpts } from '../../cli/defaults'
import { updateItemValue, writeConfig } from '../../cli/config'
import YAML from 'yaml'

import { confirm } from '../../cli/helpers'
import { NetworkContracts } from '../../cli/contracts'

interface Contract {
  name: string
  initParams: ContractInitParam[]
}

interface GeneralParam {
  contract: string // contract where the param is defined
  name: string // name of the parameter
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
    { name: 'channelDisputeEpochs', type: 'number' },
    { name: 'maxAllocationEpochs', type: 'number' },
    { name: 'delegationUnbondingPeriod', type: 'number' },
    { name: 'delegationRatio', type: 'number' },
    { name: 'rebateAlphaNumerator', type: 'number', getter: 'alphaNumerator' },
    { name: 'rebateAlphaDenominator', type: 'number', getter: 'alphaDenominator' },
  ],
}

const rewardsManager: Contract = {
  name: 'RewardsManager',
  initParams: [{ name: 'issuanceRate', type: 'BigNumber' }],
}

const contractList: Contract[] = [epochManager, curation, disputeManager, staking, rewardsManager]

const generalParams: GeneralParam[] = [
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

task('update-config', 'Update graph config parameters with onchain data')
  .addParam('graphConfig', cliOpts.graphConfig.description, cliOpts.graphConfig.default)
  .addFlag('dryRun', "Only print the changes, don't write them to the config file")
  .addFlag('skipConfirmation', cliOpts.skipConfirmation.description)
  .setAction(async (taskArgs, hre) => {
    const networkName = hre.network.name
    const configFile = taskArgs.graphConfig
    const dryRun = taskArgs.dryRun
    const skipConfirmation = taskArgs.skipConfirmation

    console.log('## Update graph config ##')
    console.log(`Network: ${networkName}`)
    console.log(`Config file: ${configFile}\n`)

    // Prompt to avoid accidentally overwriting the config file with data from another network
    if (!configFile.includes(networkName)) {
      const sure = await confirm(
        `Config file ${configFile} doesn't match 'graph.<networkName>.yml'. Are you sure you want to continue?`,
        skipConfirmation,
      )
      if (!sure) return
    }

    const { graphConfig, contracts } = hre.graph({ graphConfig: configFile })

    // general parameters
    console.log(`> General`)
    for (const param of generalParams) {
      await updateGeneralParams(contracts, param, graphConfig)
    }

    // contracts parameters
    for (const contract of contractList) {
      console.log(`> ${contract.name}`)
      await updateContractParams(contracts, contract, graphConfig)
    }

    if (dryRun) {
      console.log('\n Dry run enabled, printing changes to console (no files updated)\n')
      console.log(graphConfig.toString())
    } else {
      writeConfig(configFile, graphConfig.toString())
    }
  })

const updateGeneralParams = async (
  contracts: NetworkContracts,
  param: GeneralParam,
  config: YAML.Document.Parsed,
) => {
  const value = await contracts[param.contract][param.name]()
  const updated = updateItemValue(config, `general/${param.name}`, value)
  if (updated) {
    console.log(`\t- Updated ${param.name} to ${value}`)
  }
}

const updateContractParams = async (
  contracts: NetworkContracts,
  contract: Contract,
  config: YAML.Document.Parsed,
) => {
  for (const param of contract.initParams) {
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
