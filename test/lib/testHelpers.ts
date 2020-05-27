import { waffle as buidler } from '@nomiclabs/buidler'
import { BigNumber, bigNumberify, hexlify, randomBytes, parseEther, parseUnits } from 'ethers/utils'

export const toBN = (value: string | number) => bigNumberify(value)
export const toGRT = (value: string): BigNumber => parseUnits(value, '18')
export const randomSubgraphId = () => hexlify(randomBytes(32))
export const logStake = (stakes: any) =>
  Object.entries(stakes).map(([k, v]) => {
    console.log(k, ':', parseEther(v as string))
  })

export const provider = () => buidler.provider

// Blocks

export const latestBlock = () =>
  provider()
    .getBlockNumber()
    .then(toBN)

export const advanceBlock = () => {
  return provider().send('evm_mine', [])
}

export const advanceBlockTo = async (blockNumber: string | number | BigNumber) => {
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

// Default configuration used in tests
export const defaults = {
  curation: {
    // Reserve ratio to set bonding curve for curation (in PPM)
    reserveRatio: toBN('500000'),
    // Minimum amount required to be staked by Curators
    minimumCurationStake: toGRT('100'),
    // When one user stakes 1000, they will get 3 shares returned, as per the Bancor formula
    shareAmountFor1000Tokens: toBN('3'),
  },
  dispute: {
    minimumDeposit: toGRT('100'),
    fishermanRewardPercentage: toBN('1000'), // in basis points
    slashingPercentage: toBN('1000'), // in basis points
  },
  epochs: {
    lengthInBlocks: toBN((5 * 60) / 15), // 5 minutes in blocks
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
