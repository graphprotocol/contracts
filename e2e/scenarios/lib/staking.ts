import { BigNumberish, Signer } from 'ethers'
import { NetworkContracts } from '../../../cli/contracts'

export const stake = async (
  contracts: NetworkContracts,
  indexer: Signer,
  amount: BigNumberish,
): Promise<void> => {
  const { GraphToken, Staking } = contracts

  // Approve
  const txApprove = await GraphToken.connect(indexer).approve(Staking.address, amount)
  await txApprove.wait()

  // Stake
  const txStake = await Staking.connect(indexer).stake(amount)
  await txStake.wait()
}
