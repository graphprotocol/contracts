import { BigNumber, utils, Signer } from 'ethers'
import buidler from '@nomiclabs/buidler'

import { EpochManager } from '../../build/typechain/contracts/EpochManager'

const { hexlify, parseUnits, parseEther, randomBytes } = utils

export const toBN = (value: string | number): BigNumber => BigNumber.from(value)
export const toGRT = (value: string): BigNumber => parseUnits(value, '18')
export const randomHexBytes = (n = 32): string => hexlify(randomBytes(n))
export const logStake = (stakes: any): void => {
  Object.entries(stakes).map(([k, v]) => {
    console.log(k, ':', parseEther(v as string))
  })
}

// Network

export interface Account {
  readonly signer: Signer
  readonly address: string
}

export const provider = () => buidler.waffle.provider

export const getAccounts = async (): Promise<Account[]> => {
  const accounts = []
  const signers: Signer[] = await buidler.ethers.getSigners()
  for (const signer of signers) {
    accounts.push({ signer, address: await signer.getAddress() })
  }
  return accounts
}

export const getChainID = (): Promise<number> => {
  // HACK: this fixes ganache returning always 1 when a contract calls the chainid() opcode
  if (buidler.network.name == 'ganache') {
    return Promise.resolve(1)
  }
  return provider()
    .getNetwork()
    .then((r) => r.chainId)
}

// export const latestBlock = (): Promise<BigNumber> => provider().getBlockNumber().then(toBN)

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

export const advanceToNextEpoch = async (epochManager: EpochManager): Promise<void> => {
  const currentBlock = await latestBlock()
  const epochLength = await epochManager.epochLength()
  const nextEpochBlock = currentBlock.add(epochLength)
  await advanceBlockTo(nextEpochBlock)
}

export const evmSnapshot = async (): Promise<number> => provider().send('evm_snapshot', [])
export const evmRevert = async (id: number): Promise<boolean> => provider().send('evm_revert', [id])

// Default configuration used in tests

export const defaults = {
  curation: {
    reserveRatio: toBN('500000'),
    minimumCurationStake: toGRT('100'),
    withdrawalFeePercentage: 50000,
  },
  dispute: {
    minimumDeposit: toGRT('100'),
    fishermanRewardPercentage: toBN('1000'), // in basis points
    slashingPercentage: toBN('1000'), // in basis points
  },
  epochs: {
    lengthInBlocks: toBN((10 * 60) / 15), // 10 minutes in blocks
  },
  staking: {
    channelDisputeEpochs: 1,
    maxAllocationEpochs: 5,
    thawingPeriod: 20, // in blocks
  },
  token: {
    initialSupply: toGRT('10000000'),
  },
}
