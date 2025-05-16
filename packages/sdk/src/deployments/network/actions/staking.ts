import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { BigNumber, ethers } from 'ethers'

import { setGRTAllowances } from './graph-token'
import { randomHexBytes } from '../../../utils/bytes'

import type { GraphNetworkAction } from './types'
import type { GraphNetworkContracts } from '../deployment/contracts/load'
import { ChannelKey } from '../../../utils'

export const stake: GraphNetworkAction<{ amount: BigNumber }> = async (
  contracts: GraphNetworkContracts,
  indexer: SignerWithAddress,
  args: { amount: BigNumber },
) => {
  const { amount } = args

  // Approve
  await setGRTAllowances(contracts, indexer, [
    { spender: contracts.Staking.address, allowance: amount },
  ])
  const allowance = await contracts.GraphToken.allowance(indexer.address, contracts.Staking.address)
  console.log(`Allowance: ${ethers.utils.formatEther(allowance)}`)

  // Stake
  console.log(`\nStaking ${ethers.utils.formatEther(amount)} tokens...`)
  const tx = await contracts.Staking.connect(indexer).stake(amount)
  await tx.wait()
}

export const allocateFrom: GraphNetworkAction<{
  channelKey: ChannelKey
  subgraphDeploymentID: string
  amount: BigNumber
}> = async (
  contracts: GraphNetworkContracts,
  indexer: SignerWithAddress,
  args: { channelKey: ChannelKey; subgraphDeploymentID: string; amount: BigNumber },
): Promise<void> => {
  const { channelKey, subgraphDeploymentID, amount } = args

  const allocationId = channelKey.address
  const proof = await channelKey.generateProof(indexer.address)
  const metadata = ethers.constants.HashZero

  console.log(`\nAllocating ${amount} tokens on ${allocationId}...`)
  const extraArgs: ethers.Overrides = {}
  if (process.env.CI) {
    extraArgs.gasLimit = BigNumber.from('400000')
  }
  const tx = await contracts.Staking.connect(indexer).allocateFrom(
    indexer.address,
    subgraphDeploymentID,
    amount,
    allocationId,
    metadata,
    proof,
    extraArgs,
  )
  await tx.wait()
}

export const closeAllocation: GraphNetworkAction<{ allocationId: string }> = async (
  contracts: GraphNetworkContracts,
  indexer: SignerWithAddress,
  args: { allocationId: string },
): Promise<void> => {
  const { allocationId } = args

  const poi = randomHexBytes()

  console.log(`\nClosing ${allocationId}...`)
  const tx = await contracts.Staking.connect(indexer).closeAllocation(allocationId, poi, {
    gasLimit: 4_000_000,
  })
  await tx.wait()
}
