import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { BigNumberish } from 'ethers'
import { NetworkContracts } from '../../../cli/contracts'
import { sendTransaction } from '../../../cli/network'
import { ensureGRTAllowance } from './accounts'

export const signal = async (
  contracts: NetworkContracts,
  curator: SignerWithAddress,
  subgraphId: string,
  amount: BigNumberish,
): Promise<void> => {
  // Approve
  await ensureGRTAllowance(curator, contracts.GNS.address, amount, contracts.GraphToken)

  // Add signal
  console.log(`\nAdd ${amount} in signal to subgraphId ${subgraphId}..`)
  await sendTransaction(curator, contracts.GNS, 'mintSignal', [subgraphId, amount, 0], {
    gasLimit: 4_000_000,
  })
}
