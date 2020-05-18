/**
  Graph Token is tested in its ERC-20 capabilities by the open zeppelin tests, since it is
  part of that package.
*/

const BN = web3.utils.BN
const { expect } = require('chai')
const { AddressZero } = require('ethers/constants')
const { expectRevert, expectEvent } = require('@openzeppelin/test-helpers')

// helpers
const deployment = require('./lib/deployment')

contract('GraphToken', ([me, governor]) => {
  beforeEach(async function() {
    // Deploy graph token
    this.grt = await deployment.deployGRT(governor, {
      from: me,
    })
  })

  describe('mint', function() {
    context('> when is not minter', function() {
      describe('addMinter()', function() {
        it('reject add a new minter if not allowed', async function() {
          await expectRevert(this.grt.addMinter(me, { from: me }), 'Only Governor can call')
        })

        it('should add a new minter', async function() {
          expect(await this.grt.isMinter(me)).to.be.eq(false)
          const { logs } = await this.grt.addMinter(me, { from: governor })
          expect(await this.grt.isMinter(me)).to.be.eq(true)
          expectEvent.inLogs(logs, 'MinterAdded', {
            account: me,
          })
        })
      })

      describe('mint()', async function() {
        it('reject mint if not minter', async function() {
          await expectRevert(
            this.grt.mint(me, web3.utils.toWei(new BN('100')), { from: me }),
            'Only minter can call',
          )
        })
      })
    })

    context('> when is minter', function() {
      beforeEach(async function() {
        await this.grt.addMinter(me, { from: governor })
        expect(await this.grt.isMinter(me)).to.be.eq(true)
      })

      describe('mint()', async function() {
        it('should mint', async function() {
          const tokensBefore = await this.grt.balanceOf(me)

          const tokensToMint = web3.utils.toWei(new BN('100'))
          const { logs } = await this.grt.mint(me, tokensToMint, { from: me })

          const tokensAfter = await this.grt.balanceOf(me)
          expect(tokensAfter).to.be.bignumber.eq(tokensBefore.add(tokensToMint))
          expectEvent.inLogs(logs, 'Transfer', {
            from: AddressZero,
            to: me,
            value: tokensToMint,
          })
        })

        it('should mint if governor', async function() {
          const tokensToMint = web3.utils.toWei(new BN('100'))
          await this.grt.mint(me, tokensToMint, { from: governor })
        })
      })

      describe('removeMinter()', function() {
        it('reject remove a minter if not allowed', async function() {
          await expectRevert(this.grt.removeMinter(me, { from: me }), 'Only Governor can call')
        })

        it('should remove a minter', async function() {
          const { logs } = await this.grt.removeMinter(me, { from: governor })
          expect(await this.grt.isMinter(me)).to.be.eq(false)
          expectEvent.inLogs(logs, 'MinterRemoved', {
            account: me,
          })
        })
      })

      describe('renounceMinter()', function() {
        it('should renounce to be a minter', async function() {
          const { logs } = await this.grt.renounceMinter({ from: me })
          expect(await this.grt.isMinter(me)).to.be.eq(false)
          expectEvent.inLogs(logs, 'MinterRemoved', {
            account: me,
          })
        })
      })
    })
  })
})
