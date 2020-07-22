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

const { solidityKeccak256 } = utils

// Default configuration used in tests

export const defaults = {
  curation: {
    reserveRatio: toBN('500000'),
    minimumCurationStake: toGRT('100'),
    withdrawalFeePercentage: 50000,
  },
  dispute: {
    minimumDeposit: toGRT('100'),
    fishermanRewardPercentage: toBN('1000'), // in basis points
    slashingPercentage: toBN('1000'), // in basis points
  },
  epochs: {
    lengthInBlocks: toBN((10 * 60) / 15), // 10 minutes in blocks
  },
  staking: {
    channelDisputeEpochs: 1,
    maxAllocationEpochs: 5,
    thawingPeriod: 20, // in blocks
  },
  token: {
    initialSupply: toGRT('10000000'),
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
  return deployContract('GraphToken', owner, defaults.token.initialSupply) as Promise<GraphToken>
}

export async function deployCuration(owner: Signer, graphToken: string): Promise<Curation> {
  // Impl
  const contract = (await deployContract('Curation', owner)) as Curation

  // Proxy
  const proxy = (await deployContract('GraphProxy', owner)) as GraphProxy
  await proxy.connect(owner).setImplementation(contract.address)

  // Impl accept and initialize
  await contract
    .connect(owner)
    .acceptProxy(
      proxy.address,
      graphToken,
      defaults.curation.reserveRatio,
      defaults.curation.minimumCurationStake,
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
  return deployContract(
    'DisputeManager',
    owner,
    arbitrator,
    graphToken,
    staking,
    defaults.dispute.minimumDeposit,
    defaults.dispute.fishermanRewardPercentage,
    defaults.dispute.slashingPercentage,
  ) as Promise<DisputeManager>
}

export async function deployEpochManager(owner: Signer): Promise<EpochManager> {
  // Impl
  const contract = (await deployContract('EpochManager', owner)) as EpochManager

  // Proxy
  const proxy = (await deployContract('GraphProxy', owner)) as GraphProxy
  await proxy.connect(owner).setImplementation(contract.address)

  // Impl accept and initialize
  await contract.connect(owner).acceptProxy(proxy.address, defaults.epochs.lengthInBlocks)

  return contract.attach(proxy.address)
}

export async function deployGNS(owner: Signer, didRegistry: string): Promise<Gns> {
  return deployContract('GNS', owner, didRegistry) as Promise<Gns>
}

export async function deployEthereumDIDRegistry(owner: Signer): Promise<EthereumDidRegistry> {
  return deployContract('EthereumDIDRegistry', owner) as Promise<EthereumDidRegistry>
}

export async function deployServiceRegistry(owner: Signer): Promise<ServiceRegistry> {
  return deployContract('ServiceRegistry', owner) as Promise<ServiceRegistry>
}

export async function deployStaking(
  owner: Signer,
  graphToken: string,
  epochManager: string,
  curation: string,
): Promise<Staking> {
  // Impl
  const contract = (await deployContract('Staking', owner)) as Staking

  // Proxy
  const proxy = (await deployContract('GraphProxy', owner)) as GraphProxy
  await proxy.connect(owner).setImplementation(contract.address)

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
