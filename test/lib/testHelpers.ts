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
export const BIG_NUMBER_ZERO = BigNumber.from(0)

const toFloat = (n: BigNumber) => parseFloat(formatGRT(n))

// Network

export interface Account {
  readonly signer: Signer
  readonly address: string
}

export const provider = (): providers.JsonRpcProvider => hre.waffle.provider

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
  await advanceBlockTo(toBlock)
}

export const advanceToNextEpoch = async (epochManager: EpochManager): Promise<void> => {
  const currentBlock = await latestBlock()
  const epochLength = await epochManager.epochLength()
  const nextEpochBlock = currentBlock.add(epochLength)
  await advanceBlockTo(nextEpochBlock)
}

export const getEffectiveReserveRatio = async (
  blockNumber: BigNumber,
  createdAt: BigNumber,
  initializationPeriod: BigNumber,
  initializationExitPeriod: BigNumber,
  defaultReserveRatio: number,
): Promise<number> => {
  const _blockNumber = blockNumber.toNumber()
  const _createdAt = createdAt.toNumber()
  const _initializationPeriod = initializationPeriod.toNumber()
  const _initializationExitPeriod = initializationExitPeriod.toNumber()

  // Steady state reserve ratio
  let effectiveReserveRatio = defaultReserveRatio

  // Initialization phase reserve ratio
  if (_blockNumber <= _createdAt + _initializationPeriod) {
    effectiveReserveRatio = 1000000

    // Initialization exit phase reserve ratio
  } else if (_blockNumber <= _createdAt + _initializationPeriod + _initializationExitPeriod) {
    const percentExited =
      (_blockNumber - (_createdAt + _initializationPeriod)) / _initializationExitPeriod
    effectiveReserveRatio = 1 - (1 - defaultReserveRatio) / percentExited
  }

  return effectiveReserveRatio
}

export const calcBondingCurve = async (
  supply: BigNumber,
  reserveBalance: BigNumber,
  depositAmount: BigNumber,
  curationCreatedAt: BigNumber,
  currentBlockNumber: BigNumber,
  initializationPeriod: BigNumber,
  initializationExitPeriod: BigNumber,
  defaultReserveRatio: number,
  minimumCurationDeposit: BigNumber,
): Promise<number> => {
  const effectiveReserveRatio = await getEffectiveReserveRatio(
    currentBlockNumber,
    curationCreatedAt,
    initializationPeriod,
    initializationExitPeriod,
    defaultReserveRatio,
  )

  // Handle the initialization of the bonding curve
  if (supply.eq(0)) {
    if (depositAmount.lt(minimumCurationDeposit)) {
      throw new Error('deposit must be above minimum')
    }

    const minSupply = toGRT('1')
    return (
      (await calcBondingCurve(
        minSupply,
        minimumCurationDeposit,
        depositAmount.sub(minimumCurationDeposit),
        curationCreatedAt,
        currentBlockNumber,
        initializationPeriod,
        initializationExitPeriod,
        defaultReserveRatio,
        minimumCurationDeposit,
      )) + toFloat(minSupply)
    )
  }
  // Calculate bonding curve in the test
  return (
    toFloat(supply) *
    ((1 + toFloat(depositAmount) / toFloat(reserveBalance)) ** (effectiveReserveRatio / 1000000) -
      1)
  )
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
