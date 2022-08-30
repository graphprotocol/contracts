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
import { GraphGovernance } from '../../build/types/GraphGovernance'
import { SubgraphNFT } from '../../build/types/SubgraphNFT'
import { L1GraphTokenGateway } from '../../build/types/L1GraphTokenGateway'
import { L2GraphTokenGateway } from '../../build/types/L2GraphTokenGateway'
import { L2GraphToken } from '../../build/types/L2GraphToken'
import { BridgeEscrow } from '../../build/types/BridgeEscrow'

// Disable logging for tests
logger.pause()

// Default configuration used in tests

export const defaults = {
  curation: {
    reserveRatio: toBN('500000'),
    minimumCurationDeposit: toGRT('100'),
    curationTaxPercentage: 0,
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
  rewards: {
    issuanceRate: toGRT('1.000000023206889619'), // 5% annual rate
    dripInterval: toBN('50400'), // 1 week in blocks (post-Merge)
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

export async function deployCuration(
  deployer: Signer,
  controller: string,
  proxyAdmin: GraphProxyAdmin,
): Promise<Curation> {
  // Dependency
  const bondingCurve = (await deployContract('BancorFormula', deployer)) as unknown as BancorFormula
  const curationTokenMaster = await deployContract('GraphCurationToken', deployer)

  // Deploy
  return network.deployContractWithProxy(
    proxyAdmin,
    'Curation',
    [
      controller,
      bondingCurve.address,
      curationTokenMaster.address,
      defaults.curation.reserveRatio,
      defaults.curation.curationTaxPercentage,
      defaults.curation.minimumCurationDeposit,
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
  const bondingCurve = (await deployContract('BancorFormula', deployer)) as unknown as BancorFormula
  const subgraphDescriptor = await deployContract('SubgraphNFTDescriptor', deployer)
  const subgraphNFT = (await deployContract(
    'SubgraphNFT',
    deployer,
    await deployer.getAddress(),
  )) as SubgraphNFT

  // Deploy
  const proxy = (await network.deployContractWithProxy(
    proxyAdmin,
    'GNS',
    [controller, bondingCurve.address, subgraphNFT.address],
    deployer,
  )) as unknown as GNS

  // Post-config
  await subgraphNFT.connect(deployer).setMinter(proxy.address)
  await subgraphNFT.connect(deployer).setTokenDescriptor(subgraphDescriptor.address)

  return proxy
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
    [controller],
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

export async function deployL1GraphTokenGateway(
  deployer: Signer,
  controller: string,
  proxyAdmin: GraphProxyAdmin,
): Promise<L1GraphTokenGateway> {
  return network.deployContractWithProxy(
    proxyAdmin,
    'L1GraphTokenGateway',
    [controller],
    deployer,
  ) as unknown as L1GraphTokenGateway
}

export async function deployBridgeEscrow(
  deployer: Signer,
  controller: string,
  proxyAdmin: GraphProxyAdmin,
): Promise<BridgeEscrow> {
  return network.deployContractWithProxy(
    proxyAdmin,
    'BridgeEscrow',
    [controller],
    deployer,
  ) as unknown as BridgeEscrow
}

export async function deployL2GraphTokenGateway(
  deployer: Signer,
  controller: string,
  proxyAdmin: GraphProxyAdmin,
): Promise<L2GraphTokenGateway> {
  return network.deployContractWithProxy(
    proxyAdmin,
    'L2GraphTokenGateway',
    [controller],
    deployer,
  ) as unknown as L2GraphTokenGateway
}

export async function deployL2GRT(
  deployer: Signer,
  proxyAdmin: GraphProxyAdmin,
): Promise<L2GraphToken> {
  return network.deployContractWithProxy(
    proxyAdmin,
    'L2GraphToken',
    [await deployer.getAddress()],
    deployer,
  ) as unknown as L2GraphToken
}
