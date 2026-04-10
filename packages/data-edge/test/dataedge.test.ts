import { expect } from 'chai'
import { ethers } from 'hardhat'

import { DataEdge } from '../build/types'

describe('DataEdge', () => {
  let edge: DataEdge
  let me: Awaited<ReturnType<typeof ethers.getSigners>>[0]

  beforeEach(async () => {
    ;[me] = await ethers.getSigners()

    const factory = await ethers.getContractFactory('DataEdge', me)
    edge = await factory.deploy()
    await edge.waitForDeployment()
  })

  describe('submit data', () => {
    it('post any arbitrary data as selector', async () => {
      const txRequest = {
        data: '0x123123',
        to: await edge.getAddress(),
      }
      const tx = await me.sendTransaction(txRequest)
      const rx = await tx.wait()
      expect(rx!.status).eq(1)
    })

    it('post long calldata', async () => {
      const selector = ethers.id('setEpochBlocksPayload(bytes)').slice(0, 10)
      const messageBlocks = ethers.hexlify(ethers.randomBytes(1000))
      const txCalldata = ethers.AbiCoder.defaultAbiCoder().encode(['bytes'], [messageBlocks])
      const txData = ethers.concat([selector, txCalldata])
      const txRequest = {
        data: txData,
        to: await edge.getAddress(),
      }
      const tx = await me.sendTransaction(txRequest)
      const rx = await tx.wait()
      expect(rx!.status).eq(1)
    })
  })
})
