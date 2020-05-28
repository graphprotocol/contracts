import { expect } from 'chai'
import { AddressZero } from 'ethers/constants'

import { GraphToken } from '../build/typechain/contracts/GraphToken'

import * as deployment from './lib/deployment'
import { provider, toGRT } from './lib/testHelpers'

describe('GraphToken', () => {
  const [me, governor] = provider().getWallets()

  let grt: GraphToken

  beforeEach(async function() {
    // Deploy graph token
    grt = await deployment.deployGRT(governor.address, me)
  })

  describe('mint', function() {
    context('> when is not minter', function() {
      describe('addMinter()', function() {
        it('reject add a new minter if not allowed', async function() {
          const tx = grt.connect(me).addMinter(me.address)
          await expect(tx).to.be.revertedWith('Only Governor can call')
        })

        it('should add a new minter', async function() {
          expect(await grt.isMinter(me.address)).to.be.eq(false)
          const tx = grt.connect(governor).addMinter(me.address)
          await expect(tx)
            .to.emit(grt, 'MinterAdded')
            .withArgs(me.address)
          expect(await grt.isMinter(me.address)).to.be.eq(true)
        })
      })

      describe('mint()', async function() {
        it('reject mint if not minter', async function() {
          const tx = grt.connect(me).mint(me.address, toGRT('100'))
          await expect(tx).to.be.revertedWith('Only minter can call')
        })
      })
    })

    context('> when is minter', function() {
      beforeEach(async function() {
        await grt.connect(governor).addMinter(me.address)
        expect(await grt.isMinter(me.address)).to.be.eq(true)
      })

      describe('mint()', async function() {
        it('should mint', async function() {
          const tokensBefore = await grt.balanceOf(me.address)

          const tokensToMint = toGRT('100')
          const tx = grt.connect(me).mint(me.address, tokensToMint)
          await expect(tx)
            .to.emit(grt, 'Transfer')
            .withArgs(AddressZero, me.address, tokensToMint)

          const tokensAfter = await grt.balanceOf(me.address)
          expect(tokensAfter).to.eq(tokensBefore.add(tokensToMint))
        })

        it('should mint if governor', async function() {
          const tokensToMint = toGRT('100')
          await grt.connect(governor).mint(me.address, tokensToMint)
        })
      })

      describe('removeMinter()', function() {
        it('reject remove a minter if not allowed', async function() {
          const tx = grt.connect(me).removeMinter(me.address)
          await expect(tx).to.be.revertedWith('Only Governor can call')
        })

        it('should remove a minter', async function() {
          const tx = grt.connect(governor).removeMinter(me.address)
          await expect(tx)
            .to.emit(grt, 'MinterRemoved')
            .withArgs(me.address)
          expect(await grt.isMinter(me.address)).to.be.eq(false)
        })
      })

      describe('renounceMinter()', function() {
        it('should renounce to be a minter', async function() {
          const tx = grt.connect(me).renounceMinter()
          await expect(tx)
            .to.emit(grt, 'MinterRemoved')
            .withArgs(me.address)
          expect(await grt.isMinter(me.address)).to.be.eq(false)
        })
      })
    })
  })
})
