import fs from 'fs'
import { addCustomNetwork } from '@arbitrum/sdk'
import { applyL1ToL2Alias } from '../utils/arbitrum/'
import { impersonateAccount } from './impersonate'
import { Wallet, ethers, providers } from 'ethers'

import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

export async function getL2SignerFromL1(l1Address: string): Promise<SignerWithAddress> {
  const l2Address = applyL1ToL2Alias(l1Address)
  return impersonateAccount(l2Address)
}

export function addLocalNetwork(deploymentFile: string) {
  if (!fs.existsSync(deploymentFile)) {
    throw new Error(`Deployment file not found: ${deploymentFile}`)
  }
  const deployment = JSON.parse(fs.readFileSync(deploymentFile, 'utf-8'))
  addCustomNetwork({
    customL1Network: deployment.l1Network,
    customL2Network: deployment.l2Network,
  })
}

// Use prefunded genesis address to fund accounts
// See: https://docs.arbitrum.io/node-running/how-tos/local-dev-node#default-endpoints-and-addresses
export async function fundLocalAccounts(
  accounts: SignerWithAddress[],
  provider: providers.Provider,
) {
  for (const account of accounts) {
    const amount = ethers.utils.parseEther('10')
    const wallet = new Wallet('b6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659')
    const tx = await wallet.connect(provider).sendTransaction({
      value: amount,
      to: account.address,
    })
    await tx.wait()
  }
}
