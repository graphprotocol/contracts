import { Wallet } from 'ethers'

// Contract ABIs
import { Curation } from '../../build/typechain/contracts/Curation'
import { DisputeManager } from '../../build/typechain/contracts/DisputeManager'
import { EpochManager } from '../../build/typechain/contracts/EpochManager'
import { Gns } from '../../build/typechain/contracts/Gns'
import { RewardsManager } from '../../build/typechain/contracts/RewardsManager'
import { ServiceRegistry } from '../../build/typechain/contracts/ServiceRegistry'
import { Staking } from '../../build/typechain/contracts/Staking'
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Iens } from '../../build/typechain/contracts/Iens'
import { IPublicResolver } from '../../build/typechain/contracts/IPublicResolver'
import { IEthereumDidRegistry } from '../../build/typechain/contracts/IEthereumDidRegistry'
import { ITestRegistrar } from '../../build/typechain/contracts/ITestRegistrar'

// Contract factories
import { CurationFactory } from '../../build/typechain/contracts/CurationContract'
import { DisputeManagerFactory } from '../../build/typechain/contracts/DisputeManagerContract'
import { EpochManagerFactory } from '../../build/typechain/contracts/EpochManagerContract'
import { GnsFactory } from '../../build/typechain/contracts/GnsContract'
import { RewardsManagerFactory } from '../../build/typechain/contracts/RewardsManagerContract'
import { ServiceRegistryFactory } from '../../build/typechain/contracts/ServiceRegistryContract'
import { StakingFactory } from '../../build/typechain/contracts/StakingContract'
import { GraphTokenFactory } from '../../build/typechain/contracts/GraphTokenContract'
import { IensFactory } from '../../build/typechain/contracts/IensContract'
import { IPublicResolverFactory } from '../../build/typechain/contracts/IPublicResolverContract'
import { IEthereumDidRegistryFactory } from '../../build/typechain/contracts/IEthereumDidRegistryContract'
import { ITestRegistrarFactory } from '../../build/typechain/contracts/ITestRegistrarContract'

import { getNetworkAddresses, configureWallet } from './helpers'

interface ConnectedNetworkContracts {
  curation: Curation
  disputeManager: DisputeManager
  epochManager: EpochManager
  gns: Gns
  rewardsManager: RewardsManager
  serviceRegistry: ServiceRegistry
  staking: Staking
  token: GraphToken
  ens: Iens
  publicResolver: IPublicResolver
  ethereumDIDRegistry: IEthereumDidRegistry
  testRegistrar: ITestRegistrar
}

// Connects all contracts with basic typescript bindings
// Use this for raw txs where you must handle overrides, BN, etc. on your own
const connectContracts = async (
  wallet?: Wallet,
  network?: string,
): Promise<ConnectedNetworkContracts> => {
  const addresses = getNetworkAddresses(network)
  const configuredWallet = configureWallet(wallet, network)

  return {
    curation: CurationFactory.connect(
      addresses.generatedAddresses.Curation.address,
      configuredWallet,
    ),
    disputeManager: DisputeManagerFactory.connect(
      addresses.generatedAddresses.DisputeManager.address,
      configuredWallet,
    ),
    epochManager: EpochManagerFactory.connect(
      addresses.generatedAddresses.EpochManager.address,
      configuredWallet,
    ),
    gns: GnsFactory.connect(addresses.generatedAddresses.GNS.address, configuredWallet),
    rewardsManager: RewardsManagerFactory.connect(
      addresses.generatedAddresses.RewardsManager.address,
      configuredWallet,
    ),
    serviceRegistry: ServiceRegistryFactory.connect(
      addresses.generatedAddresses.ServiceRegistry.address,
      configuredWallet,
    ),
    staking: StakingFactory.connect(addresses.generatedAddresses.Staking.address, configuredWallet),
    token: GraphTokenFactory.connect(
      addresses.generatedAddresses.GraphToken.address,
      configuredWallet,
    ),
    ens: IensFactory.connect(addresses.permanentAddresses.ens, configuredWallet),
    publicResolver: IPublicResolverFactory.connect(
      addresses.permanentAddresses.ensPublicResolver,
      configuredWallet,
    ),
    ethereumDIDRegistry: IEthereumDidRegistryFactory.connect(
      addresses.permanentAddresses.ethereumDIDRegistry,
      configuredWallet,
    ),
    testRegistrar: ITestRegistrarFactory.connect(
      addresses.permanentAddresses.ensTestRegistrar,
      configuredWallet,
    ),
  }
}

export { connectContracts }
