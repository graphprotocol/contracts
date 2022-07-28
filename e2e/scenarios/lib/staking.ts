import hre from 'hardhat'
import { Staking } from '../../../build/types/Staking'

export const stake = async (amountWei: string): Promise<void> => {
  const graph = hre.graph()

  // Approve
  const stakeAmountWei = hre.ethers.utils.parseEther(amountWei).toString()
  await graph.contracts.GraphToken.approve(graph.contracts.Staking.address, stakeAmountWei)

  // Stake
  await graph.contracts.Staking.stake(stakeAmountWei)
}
