import { BigNumberish, Signer } from 'ethers'
import { NetworkContracts } from '../../../cli/contracts'

export const signal = async (
  contracts: NetworkContracts,
  curator: Signer,
  subgraphId: string,
  amount: BigNumberish,
): Promise<void> => {
  const { GNS } = contracts

  // Add signal
  const tx = await GNS.connect(curator).mintSignal(subgraphId, amount, 0)
  await tx.wait()
}
