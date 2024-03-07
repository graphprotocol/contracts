import hre from 'hardhat'
import { expect } from 'chai'
import { BigNumber, constants, ethers, Signature, Wallet } from 'ethers'

import { L2GraphToken } from '../../../build/types/L2GraphToken'
import { GraphToken } from '../../../build/types/GraphToken'
import { GraphNetworkContracts, Permit, signPermit, toBN, toGRT } from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { NetworkFixture } from './fixtures'

const { AddressZero, MaxUint256 } = constants

const L1SALT = '0x51f3d585afe6dfeb2af01bba0889a36c1db03beec88c6a4d0c53817069026afa'
const L2SALT = '0xe33842a7acd1d5a1d28f25a931703e5605152dc48d64dc4716efdae1f5659591'

export function grtTests(isL2: boolean): void {
  let me: Wallet
  let other: Wallet
  let governor: SignerWithAddress
  let salt: string
  let fixture: NetworkFixture
  let fixtureContracts: GraphNetworkContracts

  const graph = hre.graph()

  const mePrivateKey = '0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d'
  const otherPrivateKey = '0x6cbed15c793ce57650b9877cf6fa156fbef513c4e6134f022a85b1ffdd59b2a1'

  let grt: GraphToken | L2GraphToken

  async function permitMaxOK(): Promise<Permit> {
    return permitOK(MaxUint256)
  }

  async function permitOK(value: BigNumber): Promise<Permit> {
    const nonce = await grt.nonces(me.address)
    return {
      owner: me.address,
      spender: other.address,
      value: value,
      nonce: nonce,
      deadline: toBN('0'),
    }
  }

  async function permitExpired(): Promise<Permit> {
    const permit = await permitMaxOK()
    permit.deadline = toBN('1')
    return permit
  }

  async function permitDeny(): Promise<Permit> {
    const permit = await permitMaxOK()
    permit.value = toBN('0')
    return permit
  }

  async function createPermitTransaction(permit: Permit, signer: string, salt: string) {
    const signature: Signature = signPermit(signer, graph.chainId, grt.address, permit, salt)
    const wallet = new ethers.Wallet(signer, graph.provider)
    return grt
      .connect(wallet)
      .permit(
        permit.owner,
        permit.spender,
        permit.value,
        permit.deadline,
        signature.v,
        signature.r,
        signature.s,
      )
  }

  before(async function () {
    ({ governor } = await graph.getNamedAccounts())
    me = new ethers.Wallet(mePrivateKey, graph.provider)
    other = new ethers.Wallet(otherPrivateKey, graph.provider)

    fixture = new NetworkFixture(graph.provider)
    fixtureContracts = await fixture.load(governor, isL2)
    grt = fixtureContracts.GraphToken as GraphToken
    salt = isL2 ? L2SALT : L1SALT

    // Mint some tokens
    const tokens = toGRT('10000')
    await grt.connect(governor).mint(me.address, tokens)
  })

  describe('permit', function () {
    it('should permit max token allowance', async function () {
      // Allow to transfer tokens
      const tokensToApprove = toGRT('1000')
      const permit = await permitOK(tokensToApprove)
      const tx = createPermitTransaction(permit, mePrivateKey, salt)
      await expect(tx).emit(grt, 'Approval').withArgs(permit.owner, permit.spender, tokensToApprove)

      // Allowance updated
      const allowance = await grt.allowance(me.address, other.address)
      expect(allowance).eq(tokensToApprove)

      // Transfer tokens should work
      const tokens = toGRT('100')
      await grt.connect(other).transferFrom(me.address, other.address, tokens)
    })

    it('should permit max token allowance', async function () {
      // Allow to transfer tokens
      const permit = await permitMaxOK()
      const tx = createPermitTransaction(permit, mePrivateKey, salt)
      await expect(tx).emit(grt, 'Approval').withArgs(permit.owner, permit.spender, MaxUint256)

      // Allowance updated
      const allowance = await grt.allowance(me.address, other.address)
      expect(allowance).eq(MaxUint256)

      // Transfer tokens should work
      const tokens = toGRT('100')
      await grt.connect(other).transferFrom(me.address, other.address, tokens)
    })

    it('reject to transfer more tokens than approved by permit', async function () {
      // Allow to transfer tokens
      const tokensToApprove = toGRT('1000')
      const permit = await permitOK(tokensToApprove)
      await createPermitTransaction(permit, mePrivateKey, salt)

      // Should not transfer more than approved
      const tooManyTokens = toGRT('1001')
      const tx = grt.connect(other).transferFrom(me.address, other.address, tooManyTokens)
      await expect(tx).revertedWith('ERC20: transfer amount exceeds allowance')

      // Should transfer up to the approved amount
      await grt.connect(other).transferFrom(me.address, other.address, tokensToApprove)
    })

    it('reject use two permits with same nonce', async function () {
      // Allow to transfer tokens
      const permit = await permitMaxOK()
      await createPermitTransaction(permit, mePrivateKey, salt)

      // Try to re-use the permit
      const tx = createPermitTransaction(permit, mePrivateKey, salt)
      await expect(tx).revertedWith('GRT: invalid permit')
    })

    it('reject use expired permit', async function () {
      const permit = await permitExpired()
      const tx = createPermitTransaction(permit, mePrivateKey, salt)
      await expect(tx).revertedWith('GRT: expired permit')
    })

    it('reject permit if holder address does not match', async function () {
      const permit = await permitMaxOK()
      const tx = createPermitTransaction(permit, otherPrivateKey, salt)
      await expect(tx).revertedWith('GRT: invalid permit')
    })

    it('should deny transfer from if permit was denied', async function () {
      // Allow to transfer tokens
      const permit1 = await permitMaxOK()
      await createPermitTransaction(permit1, mePrivateKey, salt)

      // Deny transfer tokens
      const permit2 = await permitDeny()
      await createPermitTransaction(permit2, mePrivateKey, salt)

      // Allowance updated
      const allowance = await grt.allowance(me.address, other.address)
      expect(allowance).eq(toBN('0'))

      // Try to transfer without permit should fail
      const tokens = toGRT('100')
      const tx = grt.connect(other).transferFrom(me.address, other.address, tokens)
      await expect(tx).revertedWith('ERC20: transfer amount exceeds allowance')
    })
  })

  describe('mint', function () {
    describe('mint', function () {
      it('reject mint if not minter', async function () {
        const tx = grt.connect(me).mint(me.address, toGRT('100'))
        await expect(tx).revertedWith('Only minter can call')
      })
    })

    describe('addMinter', function () {
      it('reject add a new minter if not allowed', async function () {
        const tx = grt.connect(me).addMinter(me.address)
        await expect(tx).revertedWith('Only Governor can call')
      })

      it('should add a new minter', async function () {
        expect(await grt.isMinter(me.address)).eq(false)
        const tx = grt.connect(governor).addMinter(me.address)
        await expect(tx).emit(grt, 'MinterAdded').withArgs(me.address)
        expect(await grt.isMinter(me.address)).eq(true)
      })
    })

    context('> when is minter', function () {
      beforeEach(async function () {
        await grt.connect(governor).addMinter(me.address)
        expect(await grt.isMinter(me.address)).eq(true)
      })

      describe('mint', function () {
        it('should mint', async function () {
          const beforeTokens = await grt.balanceOf(me.address)

          const tokensToMint = toGRT('100')
          const tx = grt.connect(me).mint(me.address, tokensToMint)
          await expect(tx).emit(grt, 'Transfer').withArgs(AddressZero, me.address, tokensToMint)

          const afterTokens = await grt.balanceOf(me.address)
          expect(afterTokens).eq(beforeTokens.add(tokensToMint))
        })

        it('should mint if governor', async function () {
          const tokensToMint = toGRT('100')
          await grt.connect(governor).mint(me.address, tokensToMint)
        })
      })

      describe('removeMinter', function () {
        it('reject remove a minter if not allowed', async function () {
          const tx = grt.connect(me).removeMinter(me.address)
          await expect(tx).revertedWith('Only Governor can call')
        })

        it('should remove a minter', async function () {
          const tx = grt.connect(governor).removeMinter(me.address)
          await expect(tx).emit(grt, 'MinterRemoved').withArgs(me.address)
          expect(await grt.isMinter(me.address)).eq(false)
        })
      })

      describe('renounceMinter', function () {
        it('should renounce to be a minter', async function () {
          const tx = grt.connect(me).renounceMinter()
          await expect(tx).emit(grt, 'MinterRemoved').withArgs(me.address)
          expect(await grt.isMinter(me.address)).eq(false)
        })
      })
    })
  })
}
