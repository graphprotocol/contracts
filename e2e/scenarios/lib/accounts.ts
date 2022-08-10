import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { BigNumber, BigNumberish, ContractTransaction } from 'ethers'
import { ethers } from 'hardhat'
import { GraphToken } from '../../../build/types/GraphToken'
import { TransactionReceipt } from '@ethersproject/abstract-provider'
import { TransactionResponse } from '@ethersproject/providers'

const checkBalance = async (
  address: string,
  amount: BigNumber,
  getBalanceFn: (address: string) => Promise<BigNumber>,
) => {
  const balance = await getBalanceFn(address)
  if (balance.lt(amount)) {
    throw new Error(
      `Sender does not have enough funds to distribute! Required ${amount} - Balance ${balance}`,
    )
  }
}

const ensureBalance = async (
  beneficiaries: string[],
  amount: BigNumberish,
  getBalanceFn: (address: string) => Promise<BigNumber>,
  transferFn: (
    address: string,
    transferAmount: BigNumber,
  ) => Promise<ContractTransaction | TransactionResponse>,
) => {
  const txs: Promise<TransactionReceipt>[] = []
  for (const beneficiary of beneficiaries) {
    const balance = await getBalanceFn(beneficiary)
    const balanceDif = BigNumber.from(amount).sub(balance)

    if (balanceDif.gt(0)) {
      console.log(`Funding ${beneficiary} with ${balanceDif}...`)
      const tx = await transferFn(beneficiary, balanceDif)
      txs.push(tx.wait())
    }
  }
  await Promise.all(txs)
}

export const ensureETHBalance = async (
  sender: SignerWithAddress,
  beneficiaries: string[],
  amount: BigNumberish,
): Promise<void> => {
  await ensureBalance(
    beneficiaries,
    amount,
    ethers.provider.getBalance,
    (address: string, amount: BigNumber) => {
      return sender.sendTransaction({ to: address, value: amount })
    },
  )
}

export const ensureGRTAllowance = async (
  owner: SignerWithAddress,
  spender: string,
  amount: BigNumberish,
  grt: GraphToken,
): Promise<void> => {
  const allowance = await grt.allowance(owner.address, spender)
  const allowTokens = BigNumber.from(amount).sub(allowance)
  if (allowTokens.gt(0)) {
    console.log(
      `\nApproving ${spender} to spend ${allowTokens} tokens on ${owner.address} behalf...`,
    )
    await grt.connect(owner).approve(spender, amount)
  }
}

export const fundAccountsEth = async (
  sender: SignerWithAddress,
  beneficiaries: string[],
  amount: BigNumberish,
): Promise<void> => {
  // Ensure sender has enough funds to distribute
  await checkBalance(
    sender.address,
    BigNumber.from(amount).mul(beneficiaries.length),
    ethers.provider.getBalance,
  )

  // Fund the accounts
  await ensureETHBalance(sender, beneficiaries, amount)
}

export const fundAccountsGRT = async (
  sender: SignerWithAddress,
  beneficiaries: string[],
  amount: BigNumberish,
  grt: GraphToken,
): Promise<void> => {
  // Ensure sender has enough funds to distribute
  await checkBalance(
    sender.address,
    BigNumber.from(amount).mul(beneficiaries.length),
    grt.balanceOf,
  )

  // Fund the accounts
  await ensureBalance(beneficiaries, amount, grt.balanceOf, grt.connect(sender).transfer)
}
