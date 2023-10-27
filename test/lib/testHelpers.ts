import hre from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import { providers, utils, BigNumber, Signer, Wallet } from 'ethers'
import { getAddress, hexValue } from 'ethers/lib/utils'
import { toBN } from '@graphprotocol/sdk'

const { hexlify, randomBytes } = utils

export const randomHexBytes = (n = 32): string => hexlify(randomBytes(n))
export const randomAddress = (): string => getAddress(randomHexBytes(20))

// Network

export interface Account {
  readonly signer: Signer
  readonly address: string
}

export const provider = (): providers.JsonRpcProvider => hre.waffle.provider

// Enable automining with each transaction, and disable
// the mining interval. Individual tests may modify this
// behavior as needed.
export async function initNetwork(): Promise<void> {
  await provider().send('evm_setIntervalMining', [0])
  await provider().send('evm_setAutomine', [true])
}

export const getAccounts = async (): Promise<Account[]> => {
  const accounts = []
  const signers: Signer[] = await hre.ethers.getSigners()
  for (const signer of signers) {
    accounts.push({ signer, address: await signer.getAddress() })
  }
  return accounts
}

export const getChainID = (): Promise<number> => {
  // HACK: this fixes ganache returning always 1 when a contract calls the chainid() opcode
  if (hre.network.name == 'ganache') {
    return Promise.resolve(1)
  }
  return provider()
    .getNetwork()
    .then((r) => r.chainId)
}

export const evmSnapshot = async (): Promise<number> => provider().send('evm_snapshot', [])
export const evmRevert = async (id: number): Promise<boolean> => provider().send('evm_revert', [id])

// Allocation keys

interface ChannelKey {
  privKey: string
  pubKey: string
  address: string
  wallet: Signer
  generateProof: (address) => Promise<string>
}

export const deriveChannelKey = (): ChannelKey => {
  const w = Wallet.createRandom()
  return {
    privKey: w.privateKey,
    pubKey: w.publicKey,
    address: w.address,
    wallet: w,
    generateProof: (indexerAddress: string): Promise<string> => {
      const messageHash = utils.solidityKeccak256(
        ['address', 'address'],
        [indexerAddress, w.address],
      )
      const messageHashBytes = utils.arrayify(messageHash)
      return w.signMessage(messageHashBytes)
    },
  }
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

export async function setAccountBalance(address: string, newBalance: BigNumber): Promise<void> {
  await provider().send('hardhat_setBalance', [address, hexValue(newBalance)])
}

// Adapted from:
// https://github.com/livepeer/arbitrum-lpt-bridge/blob/e1a81edda3594e434dbcaa4f1ebc95b7e67ecf2a/test/utils/messaging.ts#L5
export async function getL2SignerFromL1(l1Address: string): Promise<Signer> {
  const l2Address = applyL1ToL2Alias(l1Address)
  return impersonateAccount(l2Address)
}
