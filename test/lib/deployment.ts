import { ethers } from 'ethers'
import { deployContract, getWallets, solidity } from 'ethereum-waffle'

// contracts artifacts
import CurationArtifact from '../../build/contracts/Curation.json'
import DisputeManagerArtifact from '../../build/contracts/DisputeManager.json'
import EpochManagerArtifact from '../../build/contracts/EpochManager.json'
import GNSArtifact from '../../build/contracts/GNS.json'
import GraphTokenArtifact from '../../build/contracts/GraphToken.json'
import ServiceRegistyArtifact from '../../build/contracts/ServiceRegistry.json'
import StakingArtifact from '../../build/contracts/Staking.json'

// contracts definitions
import { GraphToken } from '../../build/typechain/contracts/GraphToken'
import { Curation } from '../../build/typechain/contracts/Curation'
import { Staking } from '../../build/typechain/contracts/Staking'

// helpers
const { defaults } = require('./testHelpers')

export function deployGRT(owner: string, wallet: ethers.Wallet): Promise<GraphToken> {
  return deployContract(wallet, GraphTokenArtifact, [owner, defaults.token.initialSupply]).then(
    contract => contract as GraphToken,
  )
}

export function deployCuration(
  owner: string,
  graphToken: string,
  wallet: ethers.Wallet,
): Promise<Curation> {
  return deployContract(
    wallet,
    CurationArtifact,
    [owner, graphToken, defaults.curation.reserveRatio, defaults.curation.minimumCurationStake],
    { gasLimit: 9000000 },
  ).then(contract => contract as Curation)
}

export function deployDisputeManagerContract(
  owner: string,
  graphToken: string,
  arbitrator: string,
  staking: string,
  wallet: ethers.Wallet,
) {
  return deployContract(wallet, DisputeManagerArtifact, [
    owner,
    arbitrator,
    graphToken,
    staking,
    defaults.dispute.minimumDeposit,
    defaults.dispute.fishermanRewardPercentage,
    defaults.dispute.slashingPercentage,
  ])
}

export function deployEpochManagerContract(owner: string, wallet: ethers.Wallet) {
  return deployContract(wallet, EpochManagerArtifact, [owner, defaults.epochs.lengthInBlock])
}

export function deployGNS(owner: string, wallet: ethers.Wallet) {
  return deployContract(wallet, GNSArtifact, [owner])
}

export function deployServiceRegistry(owner: string, wallet: ethers.Wallet) {
  return deployContract(wallet, ServiceRegistyArtifact)
}

export async function deployStakingContract(
  owner: string,
  graphToken: string,
  epochManager: string,
  curation: string,
  wallet: ethers.Wallet,
) {
  const contract: Staking = (await deployContract(wallet, StakingArtifact, [
    owner,
    graphToken,
    epochManager,
  ])) as Staking

  await contract.setCuration(curation)
  await contract.setChannelDisputeEpochs(defaults.staking.channelDisputeEpochs)
  await contract.setMaxAllocationEpochs(defaults.staking.maxAllocationEpochs)
  await contract.setThawingPeriod(defaults.staking.thawingPeriod)
  return contract
}
