import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { BigNumberish } from 'ethers'
import { NetworkContracts } from '../../../cli/contracts'
import { sendTransaction } from '../../../cli/network'
import { ensureGRTAllowance } from './helpers'

export const signal = async (
  contracts: NetworkContracts,
  curator: SignerWithAddress,
  subgraphId: string,
  amount: BigNumberish,
): Promise<void> => {
  // Approve
  await ensureGRTAllowance(contracts, curator, curator.address, contracts.GNS.address, amount)

  // Add signal
  console.log(`\nAdd ${amount} in signal to subgraphId ${subgraphId}..`)
  await sendTransaction(curator, contracts.GNS, 'mintSignal', [subgraphId, amount, 0])
}
