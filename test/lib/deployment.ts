import { utils, Contract, Signer, ContractFactory } from 'ethers'
import { TransactionReceipt } from '@connext/types'
import { ChannelSigner } from '@connext/utils'
import { ethers, waffle } from '@nomiclabs/buidler'

import { toBN, toGRT } from './testHelpers'

// contracts artifacts
import MinimumViableMultisigArtifact from '../../build/contracts/MinimumViableMultisig.json'

// contracts definitions
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
    minimumIndexerStake: toGRT('1'),
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

export async function deployController(deployer: Signer): Promise<Controller> {
  return deployContract('Controller', deployer, await deployer.getAddress()) as Promise<Controller>
}

export async function deployGRT(deployer: Signer): Promise<GraphToken> {
  return deployContract('GraphToken', deployer, defaults.token.initialSupply) as Promise<GraphToken>
}

export async function deployGDAI(deployer: Signer): Promise<Gdai> {
  return deployContract('GDAI', deployer, defaults.gdai.initialSupply) as Promise<Gdai>
}

export async function deployGSR(deployer: Signer, gdaiAddress: string): Promise<GsrManager> {
  return deployContract('GSRManager', deployer, defaults.gdai.savingsRate, gdaiAddress) as Promise<
    GsrManager
  >
}

export async function deployCuration(deployer: Signer, controller: string): Promise<Curation> {
  // Impl
  const contract = (await deployContract('Curation', deployer)) as Curation

  // Proxy
  const proxy = (await deployContract('GraphProxy', deployer, contract.address)) as GraphProxy

  // Impl accept and initialize
  await contract
    .connect(deployer)
    .acceptProxy(
      proxy.address,
      controller,
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
  const contract = (await deployContract(
    'DisputeManager',
    deployer,
    controller,
    arbitrator,
    defaults.dispute.minimumDeposit,
    defaults.dispute.fishermanRewardPercentage,
    defaults.dispute.slashingPercentage,
  )) as DisputeManager

  // Config
  await contract.connect(owner).setMinimumIndexerStake(defaults.dispute.minimumIndexerStake)

  return contract
}

export async function deployEpochManager(
  deployer: Signer,
  controller: string,
): Promise<EpochManager> {
  // Impl
  const contract = (await deployContract('EpochManager', deployer)) as EpochManager

  // Proxy
  const proxy = (await deployContract('GraphProxy', deployer, contract.address)) as GraphProxy

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
  return deployContract('GNS', deployer, controller, didRegistry) as Promise<Gns>
}

export async function deployEthereumDIDRegistry(deployer: Signer): Promise<EthereumDidRegistry> {
  return deployContract('EthereumDIDRegistry', deployer) as Promise<EthereumDidRegistry>
}

export async function deployServiceRegistry(
  deployer: Signer,
  controller: string,
): Promise<ServiceRegistry> {
  return deployContract('ServiceRegistry', deployer) as Promise<ServiceRegistry>
}

export async function deployStaking(deployer: Signer, controller: string): Promise<Staking> {
  // Impl
  const contract = (await deployContract('Staking', deployer)) as Staking

  // Proxy
  const proxy = (await deployContract('GraphProxy', deployer, contract.address)) as GraphProxy

  // Impl accept and initialize
  await contract.connect(deployer).acceptProxy(proxy.address, controller)

  // Configure
  const staking = contract.attach(proxy.address)
  await staking.connect(deployer).setChannelDisputeEpochs(defaults.staking.channelDisputeEpochs)
  await staking.connect(deployer).setMaxAllocationEpochs(defaults.staking.maxAllocationEpochs)
  await staking.connect(deployer).setThawingPeriod(defaults.staking.thawingPeriod)

  return staking
}

export async function deployRewardsManager(
  deployer: Signer,
  controller: string,
): Promise<RewardsManager> {
  // Impl
  const contract = (await deployContract('RewardsManager', deployer)) as RewardsManager

  // Proxy
  const proxy = (await deployContract('GraphProxy', deployer, contract.address)) as GraphProxy

  // Impl accept and initialize
  await contract.connect(deployer).acceptProxy(proxy.address, controller)

  // Use proxy to forward calls to implementation contract
  return Promise.resolve(contract.attach(proxy.address))
}

// #### State channel contracts

export async function deployIndexerMultisig(
  node: string,
  staking: string,
  ctdt: string,
  singleAssetInterpreter: string,
  multiAssetInterpreter: string,
  withdrawInterpreter: string,
): Promise<MinimumViableMultisig> {
  return deployContract(
    'MinimumViableMultisig',
    null,
    node,
    staking,
    ctdt,
    singleAssetInterpreter,
    multiAssetInterpreter,
    withdrawInterpreter,
  ) as Promise<MinimumViableMultisig>
}

// Note: this cannot be typed properly because "ProxyFactory" is generated by the Proxy contract
async function deployProxyFactory(): Promise<Contract> {
  return deployContract('ProxyFactory') as Promise<Contract>
}

async function deployIndexerCtdt(): Promise<IndexerCtdt> {
  return deployContract('IndexerCtdt') as Promise<IndexerCtdt>
}

async function deploySingleAssetInterpreter(): Promise<IndexerSingleAssetInterpreter> {
  return deployContract('IndexerSingleAssetInterpreter') as Promise<IndexerSingleAssetInterpreter>
}

async function deployMultiAssetInterpreter(): Promise<IndexerMultiAssetInterpreter> {
  return deployContract('IndexerMultiAssetInterpreter') as Promise<IndexerMultiAssetInterpreter>
}

async function deployWithdrawInterpreter(): Promise<IndexerWithdrawInterpreter> {
  return deployContract('IndexerWithdrawInterpreter') as Promise<IndexerWithdrawInterpreter>
}

async function deployMockStaking(tokenAddress: string): Promise<MockStaking> {
  return deployContract('MockStaking', null, tokenAddress) as Promise<MockStaking>
}

async function deployMockDispute(): Promise<MockDispute> {
  return deployContract('MockDispute') as Promise<MockDispute>
}

async function deployAppWithAction(): Promise<AppWithAction> {
  return deployContract('AppWithAction') as Promise<AppWithAction>
}

async function deployIdentityApp(): Promise<IdentityApp> {
  return deployContract('IdentityApp') as Promise<IdentityApp>
}

export async function deployChannelContracts(node: string, tokenAddress: string) {
  const ctdt = await deployIndexerCtdt()
  const singleAssetInterpreter = await deploySingleAssetInterpreter()
  const multiAssetInterpreter = await deployMultiAssetInterpreter()
  const withdrawInterpreter = await deployWithdrawInterpreter()
  const mockStaking = await deployMockStaking(tokenAddress)
  const mockDispute = await deployMockDispute()
  const app = await deployAppWithAction()
  const identity = await deployIdentityApp()
  const proxyFactory = await deployProxyFactory()

  const multisigMaster = await deployIndexerMultisig(
    node,
    mockStaking.address,
    ctdt.address,
    singleAssetInterpreter.address,
    multiAssetInterpreter.address,
    withdrawInterpreter.address,
  )

  return {
    ctdt,
    singleAssetInterpreter,
    multiAssetInterpreter,
    withdrawInterpreter,
    mockStaking,
    masterCopy: multisigMaster,
    mockDispute,
    app,
    identity,
    proxyFactory,
  }
}

export async function deployMultisigWithProxy(
  node: string,
  tokenAddress: string,
  owners: ChannelSigner[],
  existingContext?: any,
) {
  const ctx = existingContext || (await deployChannelContracts(node, tokenAddress))
  const {
    ctdt,
    singleAssetInterpreter,
    multiAssetInterpreter,
    withdrawInterpreter,
    mockStaking,
    proxyFactory,
    masterCopy,
    mockDispute,
    app,
    identity,
  } = ctx
  const tx = await proxyFactory.functions.createProxyWithNonce(
    masterCopy.address,
    masterCopy.interface.encodeFunctionData('setup', [owners.map((owner) => owner.address)]),
    // hardcode ganache chainId
    solidityKeccak256(['uint256', 'uint256'], [4447, 0]),
  )
  const receipt = (await tx.wait()) as TransactionReceipt
  const { proxy: multisigAddr } = proxyFactory.interface.parseLog(receipt.logs[0]).args

  const multisig = new Contract(
    multisigAddr,
    MinimumViableMultisigArtifact.abi,
    waffle.provider,
  ) as MinimumViableMultisig

  return {
    ctdt,
    singleAssetInterpreter,
    multiAssetInterpreter,
    withdrawInterpreter,
    mockStaking,
    masterCopy,
    mockDispute,
    app,
    identity,
    proxyFactory,
    multisig,
  }
}
