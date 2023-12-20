import fs from 'fs'
import { addCustomNetwork } from '@arbitrum/sdk'
import { applyL1ToL2Alias } from '../utils/arbitrum/'
import { impersonateAccount } from './impersonate'

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
