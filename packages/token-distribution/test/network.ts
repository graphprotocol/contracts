import { BigNumber, Contract, providers, Signer, utils } from 'ethers'
import { deployments, ethers, network, waffle } from 'hardhat'

// Plugins

import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import 'hardhat-deploy'

const { hexlify, parseUnits, formatUnits, randomBytes } = utils

// Utils

export const toBN = (value: string | number): BigNumber => BigNumber.from(value)
export const toGRT = (value: string): BigNumber => parseUnits(value, '18')
export const formatGRT = (value: BigNumber): string => formatUnits(value, '18')
export const randomHexBytes = (n = 32): string => hexlify(randomBytes(n))

// Contracts

export const getContract = async (contractName: string): Promise<Contract> => {
  const deployment = await deployments.get(contractName)
  return ethers.getContractAt(contractName, deployment.address)
}

// Network

export interface Account {
  readonly signer: Signer
  readonly address: string
}

export const provider = (): providers.JsonRpcProvider => waffle.provider

export const getAccounts = async (): Promise<Account[]> => {
  const accounts: Account[] = []
  const signers: Signer[] = await ethers.getSigners()
  for (const signer of signers) {
    accounts.push({ signer, address: await signer.getAddress() })
  }
  return accounts
}

export const getChainID = (): Promise<number> => {
  // HACK: this fixes ganache returning always 1 when a contract calls the chainid() opcode
  if (network.name == 'ganache') {
    return Promise.resolve(1)
  }
  return provider()
    .getNetwork()
    .then(r => r.chainId)
}

export const latestBlockNum = (): Promise<BigNumber> => provider().getBlockNumber().then(toBN)
export const latestBlock = async (): Promise<providers.Block> => provider().getBlock(await provider().getBlockNumber())
export const latestBlockTime = async (): Promise<number> => latestBlock().then(block => block.timestamp)

export const advanceBlock = (): Promise<void> => {
  return provider().send('evm_mine', []) as Promise<void>
}

export const advanceBlockTo = async (blockNumber: string | number | BigNumber): Promise<void> => {
  const target = typeof blockNumber === 'number' || typeof blockNumber === 'string' ? toBN(blockNumber) : blockNumber
  const currentBlock = await latestBlockNum()
  const start = Date.now()
  let notified: boolean
  if (target.lt(currentBlock)) throw Error(`Target block #(${target.toString()}) is lower than current block #(${currentBlock.toString()})`)
  while ((await latestBlockNum()).lt(target)) {
    if (!notified && Date.now() - start >= 5000) {
      notified = true
      console.log(`advanceBlockTo: Advancing too ` + 'many blocks is causing this test to be slow.')
    }
    await advanceBlock()
  }
}

export const advanceBlocks = async (blocks: string | number | BigNumber): Promise<void> => {
  const steps = typeof blocks === 'number' || typeof blocks === 'string' ? toBN(blocks) : blocks
  const currentBlock = await latestBlockNum()
  const toBlock = currentBlock.add(steps)
  await advanceBlockTo(toBlock)
}

export const advanceTime = async (time: number): Promise<void> => {
  return provider().send('evm_increaseTime', [time]) as Promise<void>
}

export const advanceTimeAndBlock = async (time: number): Promise<BigNumber> => {
  await advanceTime(time)
  await advanceBlock()
  return latestBlockNum()
}

export const evmSnapshot = async (): Promise<number> => provider().send('evm_snapshot', []) as Promise<number>
export const evmRevert = async (id: number): Promise<boolean> => provider().send('evm_revert', [id]) as Promise<boolean>
