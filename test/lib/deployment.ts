import { Contract, Signer } from 'ethers'

import { logger } from '../../cli/logging'
import { network } from '../../cli'

// Contracts definitions
import { BancorFormula } from '../../build/types/BancorFormula'
import { Controller } from '../../build/types/Controller'
import { GraphProxyAdmin } from '../../build/types/GraphProxyAdmin'
import { Curation } from '../../build/types/Curation'
import { L2Curation } from '../../build/types/L2Curation'
import { DisputeManager } from '../../build/types/DisputeManager'
import { EpochManager } from '../../build/types/EpochManager'
import { GNS } from '../../build/types/GNS'
import { GraphToken } from '../../build/types/GraphToken'
import { ServiceRegistry } from '../../build/types/ServiceRegistry'
import { StakingExtension } from '../../build/types/StakingExtension'
import { IL1Staking } from '../../build/types/IL1Staking'
import { IL2Staking } from '../../build/types/IL2Staking'
import { RewardsManager } from '../../build/types/RewardsManager'
import { GraphGovernance } from '../../build/types/GraphGovernance'
import { SubgraphNFT } from '../../build/types/SubgraphNFT'
import { L1GraphTokenGateway } from '../../build/types/L1GraphTokenGateway'
import { L2GraphTokenGateway } from '../../build/types/L2GraphTokenGateway'
import { L2GraphToken } from '../../build/types/L2GraphToken'
import { BridgeEscrow } from '../../build/types/BridgeEscrow'
import { L2GNS } from '../../build/types/L2GNS'
import { L1GNS } from '../../build/types/L1GNS'
import { LibExponential } from '../../build/types/LibExponential'
import { toBN, toGRT } from '@graphprotocol/sdk'

// Disable logging for tests
// logger.pause()

// Default configuration used in tests

export const defaults = {
  curation: {
    reserveRatio: toBN('500000'),
    minimumCurationDeposit: toGRT('100'),
    l2MinimumCurationDeposit: toBN('1'),
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
    maxAllocationEpochs: 5,
    thawingPeriod: 20, // in blocks
    delegationUnbondingPeriod: 1, // in epochs
    alphaNumerator: 100,
    alphaDenominator: 100,
    lambdaNumerator: 60,
    lambdaDenominator: 100,
  },
  token: {
    initialSupply: toGRT('10000000000'), // 10 billion
  },
  rewards: {
    issuancePerBlock: toGRT('114.155251141552511415'), // 300M GRT/year
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

export async function deployL2Curation(
  deployer: Signer,
  controller: string,
  proxyAdmin: GraphProxyAdmin,
): Promise<L2Curation> {
  // Dependency
  const curationTokenMaster = await deployContract('GraphCurationToken', deployer)

  // Deploy
  return network.deployContractWithProxy(
    proxyAdmin,
    'L2Curation',
    [
      controller,
      curationTokenMaster.address,
      defaults.curation.curationTaxPercentage,
      defaults.curation.l2MinimumCurationDeposit,
    ],
    deployer,
  ) as unknown as L2Curation
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

async function deployL1OrL2GNS(
  deployer: Signer,
  controller: string,
  proxyAdmin: GraphProxyAdmin,
  isL2: boolean,
): Promise<L1GNS | L2GNS> {
  // Dependency
  const subgraphDescriptor = await deployContract('SubgraphNFTDescriptor', deployer)
  const subgraphNFT = (await deployContract(
    'SubgraphNFT',
    deployer,
    await deployer.getAddress(),
  )) as SubgraphNFT

  let name: string
  if (isL2) {
    name = 'L2GNS'
  } else {
    name = 'L1GNS'
  }
  // Deploy
  const proxy = (await network.deployContractWithProxy(
    proxyAdmin,
    name,
    [controller, subgraphNFT.address],
    deployer,
  )) as unknown as GNS

  // Post-config
  await subgraphNFT.connect(deployer).setMinter(proxy.address)
  await subgraphNFT.connect(deployer).setTokenDescriptor(subgraphDescriptor.address)

  if (isL2) {
    return proxy as L2GNS
  } else {
    return proxy as L1GNS
  }
}

export async function deployL1GNS(
  deployer: Signer,
  controller: string,
  proxyAdmin: GraphProxyAdmin,
): Promise<L1GNS> {
  return deployL1OrL2GNS(deployer, controller, proxyAdmin, false) as unknown as L1GNS
}

export async function deployL2GNS(
  deployer: Signer,
  controller: string,
  proxyAdmin: GraphProxyAdmin,
): Promise<L2GNS> {
  return deployL1OrL2GNS(deployer, controller, proxyAdmin, true) as unknown as L2GNS
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

export async function deployL1Staking(
  deployer: Signer,
  controller: string,
  proxyAdmin: GraphProxyAdmin,
): Promise<IL1Staking> {
  const extensionImpl = (await deployContract(
    'StakingExtension',
    deployer,
  )) as unknown as StakingExtension
  return (await network.deployContractWithProxy(
    proxyAdmin,
    'L1Staking',
    [
      controller,
      defaults.staking.minimumIndexerStake,
      defaults.staking.thawingPeriod,
      0,
      0,
      defaults.staking.maxAllocationEpochs,
      defaults.staking.delegationUnbondingPeriod,
      0,
      {
        alphaNumerator: defaults.staking.alphaNumerator,
        alphaDenominator: defaults.staking.alphaDenominator,
        lambdaNumerator: defaults.staking.lambdaNumerator,
        lambdaDenominator: defaults.staking.lambdaDenominator,
      },
      extensionImpl.address,
    ],
    deployer,
  )) as unknown as IL1Staking
}

export async function deployL2Staking(
  deployer: Signer,
  controller: string,
  proxyAdmin: GraphProxyAdmin,
): Promise<IL2Staking> {
  const extensionImpl = (await deployContract(
    'StakingExtension',
    deployer,
  )) as unknown as StakingExtension
  return (await network.deployContractWithProxy(
    proxyAdmin,
    'L2Staking',
    [
      controller,
      defaults.staking.minimumIndexerStake,
      defaults.staking.thawingPeriod,
      0,
      0,
      defaults.staking.maxAllocationEpochs,
      defaults.staking.delegationUnbondingPeriod,
      0,
      {
        alphaNumerator: defaults.staking.alphaNumerator,
        alphaDenominator: defaults.staking.alphaDenominator,
        lambdaNumerator: defaults.staking.lambdaNumerator,
        lambdaDenominator: defaults.staking.lambdaDenominator,
      },
      extensionImpl.address,
    ],
    deployer,
  )) as unknown as IL2Staking
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

export async function deployLibExponential(deployer: Signer): Promise<LibExponential> {
  return deployContract('LibExponential', deployer) as Promise<LibExponential>
}
