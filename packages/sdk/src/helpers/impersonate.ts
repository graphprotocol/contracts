import { impersonateAccount as hardhatImpersonateAccount } from '@nomicfoundation/hardhat-network-helpers'
import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

export async function impersonateAccount(address: string): Promise<SignerWithAddress> {
  const hre = await import('hardhat')
  await hardhatImpersonateAccount(address)

  // This allows the dynamic import to work on both ts and js
  const ethers = hre.ethers ?? hre.default.ethers
  return ethers.getSigner(address)
}
