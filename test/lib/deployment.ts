import { Contract, Signer } from 'ethers'

import { toBN, toGRT } from './testHelpers'
import { network } from '../../cli'

// Contracts definitions
import { BancorFormula } from '../../build/typechain/contracts/BancorFormula'
import { Controller } from '../../build/typechain/contracts/Controller'
import { GraphProxy } from '../../build/typechain/contracts/GraphProxy'
import { Curation } from '../../build/typechain/contracts/Curation'
import { DisputeManager } from '../../build/typechain/contracts/DisputeManager'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { Gns } from '../../build/typechain/contracts/Gns'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { ServiceRegistry } from '../../build/typechain/contracts/ServiceRegistry'
import { Staking } from '../../build/typechain/contracts/Staking'
import { RewardsManager } from '../../build/typechain/contracts/RewardsManager'
import { EthereumDidRegistry } from '../../build/typechain/contracts/EthereumDidRegistry'
import { Gdai } from '../../build/typechain/contracts/Gdai'
import { GsrManager } from '../../build/typechain/contracts/GsrManager'

// Default configuration used in tests

export const defaults = {
  curation: {
    reserveRatio: toBN('500000'),
    minimumCurationDeposit: toGRT('100'),
    withdrawalFeePercentage: 50000,
  },
  dispute: {
    minimumDeposit: toGRT('100'),
    fishermanRewardPercentage: toBN('1000'), // in basis points
    slashingPercentage: toBN('1000'), // in basis points
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
    issuanceRate: toGRT('1.000000023206889619'),
  },
}

export async function deployContract(
  contractName: string,
  deployer?: Signer,
  ...params: Array<string>
): Promise<Contract> {
  const deployResult = await network.deployContract(contractName, params, deployer, true, true)
  return deployResult.contract
}

export async function deployController(deployer: Signer): Promise<Controller> {
  return (deployContract('Controller', deployer) as unknown) as Promise<Controller>
}

export async function deployGRT(deployer: Signer): Promise<GraphToken> {
  return (deployContract(
    'GraphToken',
    deployer,
    defaults.token.initialSupply.toString(),
  ) as unknown) as Promise<GraphToken>
}

export async function deployGDAI(deployer: Signer): Promise<Gdai> {
  return (deployContract('GDAI', deployer) as unknown) as Promise<Gdai>
}

export async function deployGSR(deployer: Signer, gdaiAddress: string): Promise<GsrManager> {
  return (deployContract(
    'GSRManager',
    deployer,
    defaults.gdai.savingsRate.toString(),
    gdaiAddress,
  ) as unknown) as Promise<GsrManager>
}

export async function deployCuration(deployer: Signer, controller: string): Promise<Curation> {
  // Dependency
  const bondingCurve = ((await deployContract(
    'BancorFormula',
    deployer,
  )) as unknown) as BancorFormula

  // Impl
  const contract = ((await deployContract('Curation', deployer)) as unknown) as Curation

  // Proxy
  const proxy = ((await deployContract(
    'GraphProxy',
    deployer,
    contract.address,
  )) as unknown) as GraphProxy

  // Impl accept and initialize
  await contract
    .connect(deployer)
    .acceptProxy(
      proxy.address,
      controller,
      bondingCurve.address,
      defaults.curation.reserveRatio,
      defaults.curation.minimumCurationDeposit,
    )

  // Use proxy to forward calls to implementation contract
  return Promise.resolve(contract.attach(proxy.address))
}

export async function deployDisputeManager(
  deployer: Signer,
  controller: string,
  arbitrator: string,
): Promise<DisputeManager> {
  // Deploy
  return deployContract(
    'DisputeManager',
    deployer,
    controller,
    arbitrator,
    defaults.dispute.minimumDeposit.toString(),
    defaults.dispute.fishermanRewardPercentage.toString(),
    defaults.dispute.slashingPercentage.toString(),
  ) as Promise<DisputeManager>
}

export async function deployEpochManager(
  deployer: Signer,
  controller: string,
): Promise<EpochManager> {
  // Impl
  const contract = ((await deployContract('EpochManager', deployer)) as unknown) as EpochManager

  // Proxy
  const proxy = ((await deployContract(
    'GraphProxy',
    deployer,
    contract.address,
  )) as unknown) as GraphProxy

  // Impl accept and initialize
  await contract
    .connect(deployer)
    .acceptProxy(proxy.address, controller, defaults.epochs.lengthInBlocks)

  return contract.attach(proxy.address)
}

export async function deployGNS(
  deployer: Signer,
  controller: string,
  didRegistry: string,
): Promise<Gns> {
  // Dependency
  const bondingCurve = ((await deployContract(
    'BancorFormula',
    deployer,
  )) as unknown) as BancorFormula

  return (deployContract(
    'GNS',
    deployer,
    controller,
    bondingCurve.address,
    didRegistry,
  ) as unknown) as Promise<Gns>
}

export async function deployEthereumDIDRegistry(deployer: Signer): Promise<EthereumDidRegistry> {
  return (deployContract('EthereumDIDRegistry', deployer) as unknown) as Promise<
    EthereumDidRegistry
  >
}

export async function deployServiceRegistry(deployer: Signer): Promise<ServiceRegistry> {
  return (deployContract('ServiceRegistry', deployer) as unknown) as Promise<ServiceRegistry>
}

export async function deployStaking(deployer: Signer, controller: string): Promise<Staking> {
  // Impl
  const contract = ((await deployContract('Staking', deployer)) as unknown) as Staking

  // Proxy
  const proxy = ((await deployContract(
    'GraphProxy',
    deployer,
    contract.address,
  )) as unknown) as GraphProxy

  // Impl accept and initialize
  await contract.connect(deployer).acceptProxy(proxy.address, controller)

  // Configure
  const staking = contract.attach(proxy.address)
  await staking.connect(deployer).setMinimumIndexerStake(defaults.staking.minimumIndexerStake)
  await staking.connect(deployer).setChannelDisputeEpochs(defaults.staking.channelDisputeEpochs)
  await staking.connect(deployer).setMaxAllocationEpochs(defaults.staking.maxAllocationEpochs)
  await staking.connect(deployer).setThawingPeriod(defaults.staking.thawingPeriod)
  await staking
    .connect(deployer)
    .setDelegationUnbondingPeriod(defaults.staking.delegationUnbondingPeriod)
  await staking
    .connect(deployer)
    .setRebateRatio(defaults.staking.alphaNumerator, defaults.staking.alphaDenominator)

  return staking
}

export async function deployRewardsManager(
  deployer: Signer,
  controller: string,
): Promise<RewardsManager> {
  // Impl
  const contract = ((await deployContract('RewardsManager', deployer)) as unknown) as RewardsManager

  // Proxy
  const proxy = ((await deployContract(
    'GraphProxy',
    deployer,
    contract.address,
  )) as unknown) as GraphProxy

  // Impl accept and initialize
  await contract.connect(deployer).acceptProxy(proxy.address, controller)

  // Use proxy to forward calls to implementation contract
  return Promise.resolve(contract.attach(proxy.address))
}
