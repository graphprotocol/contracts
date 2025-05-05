import { setBalance as hardhatSetBalance } from '@nomicfoundation/hardhat-network-helpers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

import type { BigNumber } from 'ethers'

export async function setBalance(
  address: string,
  balance: BigNumber | number,
  funder?: SignerWithAddress,
) {
  try {
    await hardhatSetBalance(address, balance)
  } catch (error) {
    if (funder === undefined) throw error
    await funder.sendTransaction({ to: address, value: balance })
  }
}

export async function setBalances(
  args: { address: string; balance: BigNumber }[],
  funder?: SignerWithAddress,
) {
  for (let i = 0; i < args.length; i++) {
    await setBalance(args[i].address, args[i].balance, funder)
  }
}
