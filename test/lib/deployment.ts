import { utils, Contract, Signer, ContractFactory } from 'ethers'
import { TransactionReceipt } from '@connext/types'
import { ChannelSigner } from '@connext/utils'
import { ethers, waffle } from '@nomiclabs/buidler'

import { toBN, toGRT } from './testHelpers'

// contracts artifacts
import MinimumViableMultisigArtifact from '../../build/contracts/MinimumViableMultisig.json'

// contracts definitions
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

import { MinimumViableMultisig } from '../../build/typechain/contracts/MinimumViableMultisig'
import { IndexerCtdt } from '../../build/typechain/contracts/IndexerCtdt'
import { IndexerSingleAssetInterpreter } from '../../build/typechain/contracts/IndexerSingleAssetInterpreter'
import { IndexerMultiAssetInterpreter } from '../../build/typechain/contracts/IndexerMultiAssetInterpreter'
import { IndexerWithdrawInterpreter } from '../../build/typechain/contracts/IndexerWithdrawInterpreter'
import { MockStaking } from '../../build/typechain/contracts/MockStaking'
import { MockDispute } from '../../build/typechain/contracts/MockDispute'
import { AppWithAction } from '../../build/typechain/contracts/AppWithAction'
import { IdentityApp } from '../../build/typechain/contracts/IdentityApp'
import { Gdai } from '../../build/typechain/contracts/Gdai'
import { GsrManager } from '../../build/typechain/contracts/GsrManager'

const { solidityKeccak256 } = utils

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
    channelDisputeEpochs: 1,
    maxAllocationEpochs: 5,
    thawingPeriod: 20, // in blocks
  },
  token: {
    initialSupply: toGRT('10000000000'), // 10 billion
  },
  gdai: {
    initialSupply: toGRT('100000000'), // 100 million
    // 5% annual inflation. r^n = 1.05, where n = 365*24*60*60. 18 decimal points.
    savingsRate: toGRT('1.000000001547125958'),
  },
  rewards: {
    issuanceRate: toGRT('1.000000023206889619'),
  },
}

async function deployContract(contractName: string, deployer?: Signer, ...params) {
  let factory: ContractFactory = await ethers.getContractFactory(contractName)
  if (deployer) {
    factory = factory.connect(deployer)
  }
  return factory.deploy(...params).then((c: Contract) => c.deployed())
}

export async function deployGRT(owner: Signer): Promise<GraphToken> {
  return (deployContract('GraphToken', owner, defaults.token.initialSupply) as unknown) as Promise<
    GraphToken
  >
}

export async function deployGDAI(owner: Signer): Promise<Gdai> {
  return (deployContract('GDAI', owner, defaults.gdai.initialSupply) as unknown) as Promise<Gdai>
}

export async function deployGSR(owner: Signer, gdaiAddress: string): Promise<GsrManager> {
  return (deployContract(
    'GSRManager',
    owner,
    defaults.gdai.savingsRate,
    gdaiAddress,
  ) as unknown) as Promise<GsrManager>
}

export async function deployCuration(owner: Signer, graphToken: string): Promise<Curation> {
  // Impl
  const contract = ((await deployContract('Curation', owner)) as unknown) as Curation

  // Proxy
  const proxy = ((await deployContract(
    'GraphProxy',
    owner,
    contract.address,
  )) as unknown) as GraphProxy

  // Impl accept and initialize
  await contract
    .connect(owner)
    .acceptProxy(
      proxy.address,
      graphToken,
      defaults.curation.reserveRatio,
      defaults.curation.minimumCurationDeposit,
    )

  // Use proxy to forward calls to implementation contract
  return Promise.resolve(contract.attach(proxy.address))
}

export async function deployDisputeManager(
  owner: Signer,
  graphToken: string,
  arbitrator: string,
  staking: string,
): Promise<DisputeManager> {
  return (deployContract(
    'DisputeManager',
    owner,
    arbitrator,
    graphToken,
    staking,
    defaults.dispute.minimumDeposit,
    defaults.dispute.fishermanRewardPercentage,
    defaults.dispute.slashingPercentage,
  ) as unknown) as Promise<DisputeManager>
}

export async function deployEpochManager(owner: Signer): Promise<EpochManager> {
  // Impl
  const contract = ((await deployContract('EpochManager', owner)) as unknown) as EpochManager

  // Proxy
  const proxy = ((await deployContract(
    'GraphProxy',
    owner,
    contract.address,
  )) as unknown) as GraphProxy

  // Impl accept and initialize
  await contract.connect(owner).acceptProxy(proxy.address, defaults.epochs.lengthInBlocks)

  return contract.attach(proxy.address)
}

export async function deployGNS(
  owner: Signer,
  didRegistry: string,
  graphToken: string,
  curation: string,
): Promise<Gns> {
  return (deployContract('GNS', owner, didRegistry, graphToken, curation) as unknown) as Promise<
    Gns
  >
}

export async function deployEthereumDIDRegistry(owner: Signer): Promise<EthereumDidRegistry> {
  return (deployContract('EthereumDIDRegistry', owner) as unknown) as Promise<EthereumDidRegistry>
}

export async function deployServiceRegistry(owner: Signer): Promise<ServiceRegistry> {
  return (deployContract('ServiceRegistry', owner) as unknown) as Promise<ServiceRegistry>
}

export async function deployStaking(
  owner: Signer,
  graphToken: string,
  epochManager: string,
  curation: string,
): Promise<Staking> {
  // Impl
  const contract = ((await deployContract('Staking', owner)) as unknown) as Staking

  // Proxy
  const proxy = ((await deployContract(
    'GraphProxy',
    owner,
    contract.address,
  )) as unknown) as GraphProxy

  // Impl accept and initialize
  await contract.connect(owner).acceptProxy(proxy.address, graphToken, epochManager)

  // Configure
  const staking = contract.attach(proxy.address)
  await staking.connect(owner).setCuration(curation)
  await staking.connect(owner).setChannelDisputeEpochs(defaults.staking.channelDisputeEpochs)
  await staking.connect(owner).setMaxAllocationEpochs(defaults.staking.maxAllocationEpochs)
  await staking.connect(owner).setThawingPeriod(defaults.staking.thawingPeriod)

  return staking
}

export async function deployRewardsManager(
  owner: Signer,
  graphToken: string,
  curation: string,
  staking: string,
): Promise<RewardsManager> {
  // Impl
  const contract = ((await deployContract('RewardsManager', owner)) as unknown) as RewardsManager

  // Proxy
  const proxy = ((await deployContract(
    'GraphProxy',
    owner,
    contract.address,
  )) as unknown) as GraphProxy

  // Impl accept and initialize
  await contract
    .connect(owner)
    .acceptProxy(proxy.address, graphToken, curation, staking, defaults.rewards.issuanceRate)

  // Use proxy to forward calls to implementation contract
  return Promise.resolve(contract.attach(proxy.address))
}
