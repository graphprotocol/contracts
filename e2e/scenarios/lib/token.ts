import { BigNumberish, ContractReceipt, Signer } from 'ethers'
import { NetworkContracts } from '../../../cli/contracts'

export const airdrop = async (
  contracts: NetworkContracts,
  sender: Signer,
  beneficiaries: string[],
  amount: BigNumberish,
): Promise<void> => {
  const { GraphToken } = contracts

  const txs: Promise<ContractReceipt>[] = []

  for (const beneficiary of beneficiaries) {
    const tx = await GraphToken.connect(sender).transfer(beneficiary, amount)
    txs.push(tx.wait())
  }
  await Promise.all(txs)
}
