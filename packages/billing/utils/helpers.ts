import hre from 'hardhat'
import { utils, BigNumber, Signer } from 'ethers'
import { formatUnits } from 'ethers/lib/utils'
import { EthereumProvider } from 'hardhat/types'

const { parseUnits } = utils

export const toBN = (value: string | number): BigNumber => BigNumber.from(value)
export const toGRT = (value: string | number): BigNumber => {
  return parseUnits(typeof value === 'number' ? value.toString() : value, '18')
}
export const formatGRT = (value: BigNumber): string => formatUnits(value, '18')

export const provider = (): EthereumProvider => hre.network.provider

export interface Account {
  readonly signer: Signer
  readonly address: string
}

export const getAccounts = async (): Promise<Account[]> => {
  const accounts = []
  const signers: Signer[] = await hre.ethers.getSigners()
  for (const signer of signers) {
    accounts.push({ signer, address: await signer.getAddress() })
  }
  return accounts
}

// Adapted from:
// https://github.com/livepeer/arbitrum-lpt-bridge/blob/e1a81edda3594e434dbcaa4f1ebc95b7e67ecf2a/utils/arbitrum/messaging.ts#L118
export const applyL1ToL2Alias = (l1Address: string): string => {
  const offset = toBN('0x1111000000000000000000000000000000001111')
  const l1AddressAsNumber = toBN(l1Address)
  const l2AddressAsNumber = l1AddressAsNumber.add(offset)

  const mask = toBN(2).pow(160)
  return l2AddressAsNumber.mod(mask).toHexString()
}

export async function impersonateAccount(address: string): Promise<Signer> {
  await provider().send('hardhat_impersonateAccount', [address])
  return hre.ethers.getSigner(address)
}

// Adapted from:
// https://github.com/livepeer/arbitrum-lpt-bridge/blob/e1a81edda3594e434dbcaa4f1ebc95b7e67ecf2a/test/utils/messaging.ts#L5
export async function getL2SignerFromL1(l1Address: string): Promise<Signer> {
  const l2Address = applyL1ToL2Alias(l1Address)
  return impersonateAccount(l2Address)
}
