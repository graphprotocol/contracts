import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { BigNumber, BigNumberish, ContractTransaction } from 'ethers'
import { ethers } from 'hardhat'
import { GraphToken } from '../../../build/types/GraphToken'
import { TransactionResponse } from '@ethersproject/providers'

const checkBalance = async (
  address: string,
  amount: BigNumber,
  getBalanceFn: (address: string) => Promise<BigNumber>,
) => {
  const balance = await getBalanceFn(address)
  if (balance.lt(amount)) {
    throw new Error(
      `Sender does not have enough funds to distribute! Required ${amount} - Balance ${ethers.utils.formatEther(
        balance,
      )}`,
    )
  }
}

const ensureBalance = async (
  beneficiary: string,
  amount: BigNumberish,
  symbol: string,
  getBalanceFn: (address: string) => Promise<BigNumber>,
  transferFn: (
    address: string,
    transferAmount: BigNumber,
  ) => Promise<ContractTransaction | TransactionResponse>,
) => {
  const balance = await getBalanceFn(beneficiary)
  const balanceDif = BigNumber.from(amount).sub(balance)

  if (balanceDif.gt(0)) {
    console.log(`Funding ${beneficiary} with ${ethers.utils.formatEther(balanceDif)} ${symbol}...`)
    const tx = await transferFn(beneficiary, balanceDif)
    await tx.wait()
  }
}

export const ensureETHBalance = async (
  sender: SignerWithAddress,
  beneficiaries: string[],
  amounts: BigNumberish[],
): Promise<void> => {
  if (beneficiaries.length !== amounts.length) {
    throw new Error('beneficiaries and amounts must be the same length!')
  }
  for (let index = 0; index < beneficiaries.length; index++) {
    await ensureBalance(
      beneficiaries[index],
      amounts[index],
      'ETH',
      ethers.provider.getBalance,
      (address: string, amount: BigNumber) => {
        return sender.sendTransaction({ to: address, value: amount })
      },
    )
  }
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
      `\nApproving ${spender} to spend ${ethers.utils.formatEther(allowTokens)} GRT on ${
        owner.address
      } behalf...`,
    )
    const tx = await grt.connect(owner).approve(spender, amount)
    await tx.wait()
  }
}

export const fundAccountsETH = async (
  sender: SignerWithAddress,
  beneficiaries: string[],
  amounts: BigNumberish[],
): Promise<void> => {
  if (beneficiaries.length !== amounts.length) {
    throw new Error('beneficiaries and amounts must be the same length!')
  }
  // Ensure sender has enough funds to distribute
  const totalETH = amounts.reduce(
    (sum: BigNumber, amount: BigNumberish) => sum.add(BigNumber.from(amount)),
    BigNumber.from(0),
  )
  await checkBalance(sender.address, BigNumber.from(totalETH), ethers.provider.getBalance)

  // Fund the accounts
  await ensureETHBalance(sender, beneficiaries, amounts)
}

export const fundAccountsGRT = async (
  sender: SignerWithAddress,
  beneficiaries: string[],
  amounts: BigNumberish[],
  grt: GraphToken,
): Promise<void> => {
  if (beneficiaries.length !== amounts.length) {
    throw new Error('beneficiaries and amounts must be the same length!')
  }
  // Ensure sender has enough funds to distribute
  const totalGRT = amounts.reduce(
    (sum: BigNumber, amount: BigNumberish) => sum.add(BigNumber.from(amount)),
    BigNumber.from(0),
  )
  await checkBalance(sender.address, BigNumber.from(totalGRT), grt.balanceOf)

  // Fund the accounts
  for (let index = 0; index < beneficiaries.length; index++) {
    await ensureBalance(
      beneficiaries[index],
      amounts[index],
      'GRT',
      grt.balanceOf,
      grt.connect(sender).transfer,
    )
  }
}
