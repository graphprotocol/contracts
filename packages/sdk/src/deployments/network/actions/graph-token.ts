import { BigNumber, ethers } from 'ethers'

import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import type { GraphNetworkContracts, GraphNetworkAction } from '../..'

export const setGRTBalances: GraphNetworkAction<
  {
    address: string
    balance: BigNumber
  }[]
> = async (
  contracts: GraphNetworkContracts,
  signer: SignerWithAddress,
  args: { address: string; balance: BigNumber }[],
): Promise<void> => {
  for (const arg of args) {
    await setGRTBalance(contracts, signer, { address: arg.address, balance: arg.balance })
  }
}

export const setGRTBalance: GraphNetworkAction<{
  address: string
  balance: BigNumber
}> = async (
  contracts: GraphNetworkContracts,
  signer: SignerWithAddress,
  args: { address: string; balance: BigNumber },
): Promise<void> => {
  const { address, balance } = args

  const currentBalance = await contracts.GraphToken.balanceOf(address)
  const balanceDif = BigNumber.from(balance).sub(currentBalance)

  if (balanceDif.gt(0)) {
    console.log(`Funding ${address} with ${ethers.utils.formatEther(balanceDif)} GRT...`)
    const tx = await contracts.GraphToken.connect(signer).transfer(address, balanceDif)
    await tx.wait()
  }
}

export const setGRTAllowances: GraphNetworkAction<
  { spender: string; allowance: BigNumber }[]
> = async (
  contracts: GraphNetworkContracts,
  signer: SignerWithAddress,
  args: { spender: string; allowance: BigNumber }[],
): Promise<void> => {
  for (const arg of args) {
    await setGRTAllowance(contracts, signer, {
      spender: arg.spender,
      allowance: arg.allowance,
    })
  }
}

export const setGRTAllowance: GraphNetworkAction<{
  spender: string
  allowance: BigNumber
}> = async (
  contracts: GraphNetworkContracts,
  signer: SignerWithAddress,
  args: { spender: string; allowance: BigNumber },
): Promise<void> => {
  const { spender, allowance } = args

  const currentAllowance = await contracts.GraphToken.allowance(signer.address, spender)
  if (!currentAllowance.eq(allowance)) {
    console.log(
      `Approving ${spender} with ${ethers.utils.formatEther(allowance)} GRT on behalf of ${
        signer.address
      }...`,
    )
    const tx = await contracts.GraphToken.connect(signer).approve(spender, allowance)
    await tx.wait()
  }
}
