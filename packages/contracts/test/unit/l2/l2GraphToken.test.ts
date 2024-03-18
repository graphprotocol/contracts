import hre from 'hardhat'
import { expect } from 'chai'

import { L2GraphToken } from '../../../build/types/L2GraphToken'

import { grtTests } from '../lib/graphTokenTests'
import { NetworkFixture } from '../lib/fixtures'
import { GraphNetworkContracts, toGRT } from '@graphprotocol/sdk'
import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

describe('L2GraphToken', () => {
  describe('Base GRT behavior', () => {
    grtTests.bind(this)(true)
  })
  describe('Extended L2 behavior', () => {
    const graph = hre.graph()
    let mockL2Gateway: SignerWithAddress
    let mockL1GRT: SignerWithAddress
    let governor: SignerWithAddress
    let user: SignerWithAddress

    let contracts: GraphNetworkContracts
    let fixture: NetworkFixture
    let grt: L2GraphToken

    before(async function () {
      [mockL1GRT, mockL2Gateway, user] = await graph.getTestAccounts()
      ;({ governor } = await graph.getNamedAccounts())
      fixture = new NetworkFixture(graph.provider)
      contracts = await fixture.load(governor, true)
      grt = contracts.L2GraphToken
    })

    beforeEach(async function () {
      await fixture.setUp()
    })

    afterEach(async function () {
      await fixture.tearDown()
    })

    describe('setGateway', function () {
      it('cannot be called by someone who is not the governor', async function () {
        const tx = grt.connect(mockL2Gateway).setGateway(mockL2Gateway.address)
        await expect(tx).revertedWith('Only Governor can call')
      })
      it('sets the L2 Gateway address when called by the governor', async function () {
        const tx = grt.connect(governor).setGateway(mockL2Gateway.address)
        await expect(tx).emit(grt, 'GatewaySet').withArgs(mockL2Gateway.address)
        expect(await grt.gateway()).eq(mockL2Gateway.address)
      })
    })
    describe('setL1Address', function () {
      it('cannot be called by someone who is not the governor', async function () {
        const tx = grt.connect(mockL2Gateway).setL1Address(mockL1GRT.address)
        await expect(tx).revertedWith('Only Governor can call')
      })
      it('sets the L1 GRT address when called by the governor', async function () {
        const tx = grt.connect(governor).setL1Address(mockL1GRT.address)
        await expect(tx).emit(grt, 'L1AddressSet').withArgs(mockL1GRT.address)
        expect(await grt.l1Address()).eq(mockL1GRT.address)
      })
    })
    describe('bridge minting and burning', function () {
      beforeEach(async function () {
        // Configure the l1Address and gateway
        await grt.connect(governor).setL1Address(mockL1GRT.address)
        await grt.connect(governor).setGateway(mockL2Gateway.address)
      })
      describe('bridgeMint', function () {
        it('cannot be called by someone who is not the gateway', async function () {
          const tx = grt.connect(governor).bridgeMint(user.address, toGRT('100'))
          await expect(tx).revertedWith('NOT_GATEWAY')
        })
        it('mints GRT into a destination account', async function () {
          const tx = grt.connect(mockL2Gateway).bridgeMint(user.address, toGRT('100'))
          await expect(tx).emit(grt, 'BridgeMinted').withArgs(user.address, toGRT('100'))
          expect(await grt.balanceOf(user.address)).eq(toGRT('100'))
        })
      })
      describe('bridgeBurn', function () {
        it('cannot be called by someone who is not the gateway', async function () {
          const tx = grt.connect(governor).bridgeBurn(user.address, toGRT('100'))
          await expect(tx).revertedWith('NOT_GATEWAY')
        })
        it('requires approval for burning', async function () {
          await grt.connect(mockL2Gateway).bridgeMint(user.address, toGRT('100'))
          const tx = grt.connect(mockL2Gateway).bridgeBurn(user.address, toGRT('20'))
          await expect(tx).revertedWith('ERC20: burn amount exceeds allowance')
        })
        it('fails if the user does not have enough funds', async function () {
          await grt.connect(mockL2Gateway).bridgeMint(user.address, toGRT('10'))
          await grt.connect(user).approve(mockL2Gateway.address, toGRT('20'))
          const tx = grt.connect(mockL2Gateway).bridgeBurn(user.address, toGRT('20'))
          await expect(tx).revertedWith('ERC20: burn amount exceeds balance')
        })
        it('burns GRT from an account when approved', async function () {
          await grt.connect(mockL2Gateway).bridgeMint(user.address, toGRT('100'))
          await grt.connect(user).approve(mockL2Gateway.address, toGRT('20'))
          const tx = grt.connect(mockL2Gateway).bridgeBurn(user.address, toGRT('20'))
          await expect(tx).emit(grt, 'BridgeBurned').withArgs(user.address, toGRT('20'))
          expect(await grt.balanceOf(user.address)).eq(toGRT('80'))
        })
      })
      it('does not allow the bridge to mint as a regular minter', async function () {
        const tx = grt.connect(mockL2Gateway).mint(user.address, toGRT('100'))
        await expect(tx).revertedWith('Only minter can call')
      })
    })
  })
})
