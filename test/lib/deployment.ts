import { Contract, Signer } from 'ethers'

import { toBN, toGRT } from './testHelpers'
import { logger } from '../../cli/logging'
import { network } from '../../cli'

// Contracts definitions
import { BancorFormula } from '../../build/types/BancorFormula'
import { Controller } from '../../build/types/Controller'
import { GraphProxyAdmin } from '../../build/types/GraphProxyAdmin'
import { Curation } from '../../build/types/Curation'
import { DisputeManager } from '../../build/types/DisputeManager'
import { EpochManager } from '../../build/types/EpochManager'
import { GNS } from '../../build/types/GNS'
import { GraphToken } from '../../build/types/GraphToken'
import { ServiceRegistry } from '../../build/types/ServiceRegistry'
import { Staking } from '../../build/types/Staking'
import { RewardsManager } from '../../build/types/RewardsManager'
import { EthereumDIDRegistry } from '../../build/types/EthereumDIDRegistry'
import { GDAI } from '../../build/types/GDAI'
import { GSRManager } from '../../build/types/GSRManager'
import { GraphGovernance } from '../../build/types/GraphGovernance'

// Disable logging for tests
logger.pause()

// Default configuration used in tests

export interface CurationLoadOptions {
  initializationDays?: number
  initializationExitDays?: number
  blocksPerDay?: number
}

export const defaults = {
  curation: {
    reserveRatio: toBN('500000'),
    minimumCurationDeposit: toGRT('100'),
    curationTaxPercentage: 0,
    initializationDays: 1,
    initializationExitDays: 2,
    blocksPerDay: 1,
  },
  dispute: {
    minimumDeposit: toGRT('100'),
    fishermanRewardPercentage: toBN('1000'), // in basis points
    qrySlashingPercentage: toBN('1000'), // in basis points
    idxSlashingPercentage: toBN('100000'), // in basis points
  },
  epochs: {
    lengthInBlocks: toBN((15 * 60) / 15), // 15 minutes in blocks
  },
  staking: {
    minimumIndexerStake: toGRT('10'),
    channelDisputeEpochs: 1,
    maxAllocationEpochs: 5,
    thawingPeriod: 20, // in blocks
    delegationUnbondingPeriod: 1, // in epochs
    alphaNumerator: 85,
    alphaDenominator: 100,
  },
  token: {
    initialSupply: toGRT('10000000000'), // 10 billion
  },
  gdai: {
    // 5% annual inflation. r^n = 1.05, where n = 365*24*60*60. 18 decimal points.
    savingsRate: toGRT('1.000000001547125958'),
    initialSupply: toGRT('100000000'), // 100 M
  },
  rewards: {
    issuanceRate: toGRT('1.000000023206889619'), // 5% annual rate
  },
}

export async function deployProxy(
  implementation: string,
  proxyAdmin: string,
  deployer: Signer,
): Promise<Contract> {
  const deployResult = await network.deployProxy(implementation, proxyAdmin, deployer)
  return deployResult.contract
}

export async function deployContract(
  contractName: string,
  deployer?: Signer,
  ...params: Array<string>
): Promise<Contract> {
  const deployResult = await network.deployContract(contractName, params, deployer, true)
  return deployResult.contract
}

export async function deployProxyAdmin(deployer: Signer): Promise<GraphProxyAdmin> {
  return deployContract('GraphProxyAdmin', deployer) as Promise<GraphProxyAdmin>
}

export async function deployController(deployer: Signer): Promise<Controller> {
  return deployContract('Controller', deployer) as unknown as Promise<Controller>
}

export async function deployGRT(deployer: Signer): Promise<GraphToken> {
  return deployContract(
    'GraphToken',
    deployer,
    defaults.token.initialSupply.toString(),
  ) as unknown as Promise<GraphToken>
}

export async function deployGDAI(deployer: Signer): Promise<GDAI> {
  return deployContract('GDAI', deployer) as unknown as Promise<GDAI>
}

export async function deployGSR(deployer: Signer, gdaiAddress: string): Promise<GSRManager> {
  return deployContract(
    'GSRManager',
    deployer,
    defaults.gdai.savingsRate.toString(),
    gdaiAddress,
  ) as unknown as Promise<GSRManager>
}

export async function deployCuration(
  deployer: Signer,
  controller: string,
  proxyAdmin: GraphProxyAdmin,
  options?: CurationLoadOptions,
): Promise<Curation> {
  // Dependency
  const bondingCurve = (await deployContract('BancorFormula', deployer)) as unknown as BancorFormula

  // Deploy
  return network.deployContractWithProxy(
    proxyAdmin,
    'Curation',
    [
      controller,
      bondingCurve.address,
      defaults.curation.reserveRatio,
      defaults.curation.curationTaxPercentage,
      defaults.curation.minimumCurationDeposit,
      options?.initializationDays || defaults.curation.initializationDays,
      options?.initializationExitDays || defaults.curation.initializationExitDays,
      options?.blocksPerDay || defaults.curation.blocksPerDay,
    ],
    deployer,
  ) as unknown as Curation
}

export async function deployDisputeManager(
  deployer: Signer,
  controller: string,
  arbitrator: string,
  proxyAdmin: GraphProxyAdmin,
): Promise<DisputeManager> {
  // Deploy
  return network.deployContractWithProxy(
    proxyAdmin,
    'DisputeManager',
    [
      controller,
      arbitrator,
      defaults.dispute.minimumDeposit.toString(),
      defaults.dispute.fishermanRewardPercentage.toString(),
      defaults.dispute.qrySlashingPercentage.toString(),
      defaults.dispute.idxSlashingPercentage.toString(),
    ],
    deployer,
  ) as Promise<DisputeManager>
}

export async function deployEpochManager(
  deployer: Signer,
  controller: string,
  proxyAdmin: GraphProxyAdmin,
): Promise<EpochManager> {
  return network.deployContractWithProxy(
    proxyAdmin,
    'EpochManager',
    [controller, defaults.epochs.lengthInBlocks],
    deployer,
  ) as unknown as EpochManager
}

export async function deployGNS(
  deployer: Signer,
  controller: string,
  proxyAdmin: GraphProxyAdmin,
): Promise<GNS> {
  // Dependency
  const didRegistry = await deployEthereumDIDRegistry(deployer)
  const bondingCurve = (await deployContract('BancorFormula', deployer)) as unknown as BancorFormula

  // Deploy
  return network.deployContractWithProxy(
    proxyAdmin,
    'GNS',
    [controller, bondingCurve.address, didRegistry.address],
    deployer,
  ) as unknown as GNS
}

export async function deployEthereumDIDRegistry(deployer: Signer): Promise<EthereumDIDRegistry> {
  return deployContract('EthereumDIDRegistry', deployer) as unknown as Promise<EthereumDIDRegistry>
}

export async function deployServiceRegistry(
  deployer: Signer,
  controller: string,
  proxyAdmin: GraphProxyAdmin,
): Promise<ServiceRegistry> {
  // Deploy
  return network.deployContractWithProxy(
    proxyAdmin,
    'ServiceRegistry',
    [controller],
    deployer,
  ) as unknown as Promise<ServiceRegistry>
}

export async function deployStaking(
  deployer: Signer,
  controller: string,
  proxyAdmin: GraphProxyAdmin,
): Promise<Staking> {
  return network.deployContractWithProxy(
    proxyAdmin,
    'Staking',
    [
      controller,
      defaults.staking.minimumIndexerStake,
      defaults.staking.thawingPeriod,
      0,
      0,
      defaults.staking.channelDisputeEpochs,
      defaults.staking.maxAllocationEpochs,
      defaults.staking.delegationUnbondingPeriod,
      0,
      defaults.staking.alphaNumerator,
      defaults.staking.alphaDenominator,
    ],
    deployer,
  ) as unknown as Staking
}

export async function deployRewardsManager(
  deployer: Signer,
  controller: string,
  proxyAdmin: GraphProxyAdmin,
): Promise<RewardsManager> {
  return network.deployContractWithProxy(
    proxyAdmin,
    'RewardsManager',
    [controller, defaults.rewards.issuanceRate],
    deployer,
  ) as unknown as RewardsManager
}

export async function deployGraphGovernance(
  deployer: Signer,
  governor: string,
  proxyAdmin: GraphProxyAdmin,
): Promise<GraphGovernance> {
  return network.deployContractWithProxy(
    proxyAdmin,
    'GraphGovernance',
    [governor],
    deployer,
  ) as unknown as GraphGovernance
}
