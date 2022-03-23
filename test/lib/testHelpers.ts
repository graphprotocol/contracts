import hre from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import { providers, utils, BigNumber, Signer, Wallet } from 'ethers'
import { formatUnits, getAddress } from 'ethers/lib/utils'

import { EpochManager } from '../../build/types/EpochManager'

const { hexlify, parseUnits, randomBytes } = utils

export const toBN = (value: string | number): BigNumber => BigNumber.from(value)
export const toGRT = (value: string | number): BigNumber => {
  return parseUnits(typeof value === 'number' ? value.toString() : value, '18')
}
export const formatGRT = (value: BigNumber): string => formatUnits(value, '18')
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

export const latestBlock = (): Promise<BigNumber> =>
  provider().send('eth_blockNumber', []).then(toBN)

export const advanceBlock = (): Promise<void> => {
  return provider().send('evm_mine', [])
}

export const advanceBlockTo = async (blockNumber: string | number | BigNumber): Promise<void> => {
  const target =
    typeof blockNumber === 'number' || typeof blockNumber === 'string'
      ? toBN(blockNumber)
      : blockNumber
  const currentBlock = await latestBlock()
  const start = Date.now()
  let notified
  if (target.lt(currentBlock))
    throw Error(`Target block #(${target}) is lower than current block #(${currentBlock})`)
  while ((await latestBlock()).lt(target)) {
    if (!notified && Date.now() - start >= 5000) {
      notified = true
      console.log(`advanceBlockTo: Advancing too ` + 'many blocks is causing this test to be slow.')
    }
    await advanceBlock()
  }
}

export const advanceBlocks = async (blocks: string | number | BigNumber): Promise<void> => {
  const steps = typeof blocks === 'number' || typeof blocks === 'string' ? toBN(blocks) : blocks
  const currentBlock = await latestBlock()
  const toBlock = currentBlock.add(steps)
  return advanceBlockTo(toBlock)
}

export const advanceToNextEpoch = async (epochManager: EpochManager): Promise<void> => {
  const blocksSinceEpoch = await epochManager.currentEpochBlockSinceStart()
  const epochLen = await epochManager.epochLength()
  return advanceBlocks(epochLen.sub(blocksSinceEpoch))
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
