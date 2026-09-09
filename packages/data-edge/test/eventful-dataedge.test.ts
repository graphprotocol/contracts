import { expect } from 'chai'
import { ethers } from 'hardhat'

import { EventfulDataEdge } from '../build/types'

describe('EventfulDataEdge', () => {
  let edge: EventfulDataEdge
  let me: Awaited<ReturnType<typeof ethers.getSigners>>[0]

  beforeEach(async () => {
    ;[me] = await ethers.getSigners()

    const factory = await ethers.getContractFactory('EventfulDataEdge', me)
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
      const event = edge.interface.parseLog({ topics: rx!.logs[0].topics as string[], data: rx!.logs[0].data })
      expect(event!.args.data).eq(txRequest.data)
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
      const event = edge.interface.parseLog({ topics: rx!.logs[0].topics as string[], data: rx!.logs[0].data })
      expect(event!.args.data).eq(txRequest.data)
    })
  })
})
