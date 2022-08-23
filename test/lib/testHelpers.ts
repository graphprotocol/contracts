import hre from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import { providers, utils, BigNumber, Signer, Wallet } from 'ethers'
import { formatUnits, getAddress, hexValue } from 'ethers/lib/utils'
import { BigNumber as BN } from 'bignumber.js'

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
  if (target.lt(currentBlock)) {
    throw Error(`Target block #(${target}) is lower than current block #(${currentBlock})`)
  } else if (target.eq(currentBlock)) {
    return
  } else {
    await advanceBlocks(target.sub(currentBlock))
  }
}

export const advanceBlocks = async (blocks: string | number | BigNumber): Promise<void> => {
  const blocksBN = BigNumber.from(blocks)
  const maxIterativeBlocks = BigNumber.from(10)
  if (blocksBN.lte(maxIterativeBlocks)) {
    for (let n = 0; blocksBN.gt(n); n++) {
      await advanceBlock()
    }
  } else {
    await provider().send('hardhat_mine', [hexValue(blocksBN)])
  }
}

export const advanceToNextEpoch = async (epochManager: EpochManager): Promise<void> => {
  const blocksSinceEpoch = await epochManager.currentEpochBlockSinceStart()
  const epochLen = await epochManager.epochLength()
  return advanceBlocks(epochLen.sub(blocksSinceEpoch))
}

export const advanceEpochs = async (epochManager: EpochManager, n: number): Promise<void> => {
  for (let i = 0; i < n; i++) {
    await advanceToNextEpoch(epochManager)
  }
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

// Core formula that gets accumulated rewards for a period of time
const getRewards = (p: BN, r: BN, t: BN): string => {
  BN.config({ POW_PRECISION: 100 })
  return p.times(r.pow(t)).minus(p).precision(18).toString(10)
}

// Tracks the accumulated rewards as supply changes across snapshots
// both at a global level (like the Reservoir) and per signal (like RewardsManager)
export class RewardsTracker {
  totalSupply = BigNumber.from(0)
  lastUpdatedBlock = BigNumber.from(0)
  lastPerSignalUpdatedBlock = BigNumber.from(0)
  accumulated = BigNumber.from(0)
  accumulatedPerSignal = BigNumber.from(0)
  accumulatedAtLastPerSignalUpdatedBlock = BigNumber.from(0)
  issuanceRate = BigNumber.from(0)

  static async create(
    initialSupply: BigNumber,
    issuanceRate: BigNumber,
    updatedBlock?: BigNumber,
  ): Promise<RewardsTracker> {
    const lastUpdatedBlock = updatedBlock || (await latestBlock())
    const tracker = new RewardsTracker(initialSupply, issuanceRate, lastUpdatedBlock)
    return tracker
  }

  constructor(initialSupply: BigNumber, issuanceRate: BigNumber, updatedBlock: BigNumber) {
    this.issuanceRate = issuanceRate
    this.totalSupply = initialSupply
    this.lastUpdatedBlock = updatedBlock
    this.lastPerSignalUpdatedBlock = updatedBlock
  }

  async snapshotRewards(initialSupply?: BigNumber, atBlock?: BigNumber): Promise<BigNumber> {
    const newRewards = await this.newRewards(atBlock)
    this.accumulated = this.accumulated.add(newRewards)
    this.totalSupply = initialSupply || this.totalSupply.add(newRewards)
    this.lastUpdatedBlock = atBlock || (await latestBlock())
    return this.accumulated
  }

  async snapshotPerSignal(totalSignal: BigNumber, atBlock?: BigNumber): Promise<BigNumber> {
    this.accumulatedPerSignal = await this.accRewardsPerSignal(totalSignal, atBlock)
    this.accumulatedAtLastPerSignalUpdatedBlock = await this.accRewards(atBlock)
    this.lastPerSignalUpdatedBlock = atBlock || (await latestBlock())
    return this.accumulatedPerSignal
  }

  async elapsedBlocks(): Promise<BigNumber> {
    const currentBlock = await latestBlock()
    return currentBlock.sub(this.lastUpdatedBlock)
  }

  async newRewardsPerSignal(totalSignal: BigNumber, atBlock?: BigNumber): Promise<BigNumber> {
    const accRewards = await this.accRewards(atBlock)
    const diff = accRewards.sub(this.accumulatedAtLastPerSignalUpdatedBlock)
    if (totalSignal.eq(0)) {
      return BigNumber.from(0)
    }
    return diff.mul(toGRT(1)).div(totalSignal)
  }

  async accRewardsPerSignal(totalSignal: BigNumber, atBlock?: BigNumber): Promise<BigNumber> {
    return this.accumulatedPerSignal.add(await this.newRewardsPerSignal(totalSignal, atBlock))
  }

  async newRewards(atBlock?: BigNumber): Promise<BigNumber> {
    if (!atBlock) {
      atBlock = await latestBlock()
    }
    const nBlocks = atBlock.sub(this.lastUpdatedBlock)
    return this.accruedByElapsed(nBlocks)
  }

  async accRewards(atBlock?: BigNumber): Promise<BigNumber> {
    if (!atBlock) {
      atBlock = await latestBlock()
    }
    return this.accumulated.add(await this.newRewards(atBlock))
  }

  async accruedByElapsed(nBlocks: BigNumber | number): Promise<BigNumber> {
    const n = getRewards(
      new BN(this.totalSupply.toString()),
      new BN(this.issuanceRate.toString()).div(1e18),
      new BN(nBlocks.toString()),
    )
    return BigNumber.from(n)
  }
}

// Adapted from:
// https://github.com/livepeer/arbitrum-lpt-bridge/blob/e1a81edda3594e434dbcaa4f1ebc95b7e67ecf2a/test/utils/messaging.ts#L5
export async function getL2SignerFromL1(l1Address: string): Promise<Signer> {
  const l2Address = applyL1ToL2Alias(l1Address)
  await provider().send('hardhat_impersonateAccount', [l2Address])
  const l2Signer = await hre.ethers.getSigner(l2Address)

  return l2Signer
}
