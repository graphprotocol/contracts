import { expect, use } from 'chai'
import { constants, utils, BytesLike, BigNumber, Signature } from 'ethers'
import { solidity } from 'ethereum-waffle'
import { eip712 } from '@graphprotocol/common-ts/dist/attestations'

import { GraphToken } from '../build/typechain/contracts/GraphToken'

import * as deployment from './lib/deployment'
import { getChainID, provider, toBN, toGRT } from './lib/testHelpers'

use(solidity)

const { AddressZero, MaxUint256 } = constants
const { keccak256, SigningKey } = utils

const PERMIT_TYPE_HASH = eip712.typeHash(
  'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)',
)
const SALT = '0x51f3d585afe6dfeb2af01bba0889a36c1db03beec88c6a4d0c53817069026afa'

interface Permit {
  owner: string
  spender: string
  value: BigNumber
  nonce: BigNumber
  deadline: BigNumber
}

function hashEncodePermit(permit: Permit) {
  return eip712.hashStruct(
    PERMIT_TYPE_HASH,
    ['address', 'address', 'uint256', 'uint256', 'uint256'],
    [permit.owner, permit.spender, permit.value, permit.nonce, permit.deadline],
  )
}

function signPermit(
  signer: BytesLike,
  chainId: number,
  contractAddress: string,
  permit: Permit,
): Signature {
  const domainSeparator = eip712.domainSeparator({
    name: 'Graph Token',
    version: '0',
    chainId,
    verifyingContract: contractAddress,
    salt: SALT,
  })
  const hashEncodedPermit = hashEncodePermit(permit)
  const message = eip712.encode(domainSeparator, hashEncodedPermit)
  const messageHash = keccak256(message)
  const signingKey = new SigningKey(signer)
  return signingKey.signDigest(messageHash)
}

describe('GraphToken', () => {
  const [me, other, governor] = provider().getWallets()

  let grt: GraphToken

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

  async function createPermitTransaction(permit: Permit, signer: string) {
    const chainID = (await getChainID()) as number
    const signature: Signature = signPermit(signer, chainID, grt.address, permit)

    return grt.permit(
      permit.owner,
      permit.spender,
      permit.value,
      permit.deadline,
      signature.v,
      signature.r,
      signature.s,
    )
  }

  beforeEach(async function() {
    // Deploy graph token
    grt = await deployment.deployGRT(governor.address)

    // Mint some tokens
    const tokens = toGRT('10000')
    await grt.connect(governor).mint(me.address, tokens)
  })

  describe('permit', function() {
    it('should permit max token allowance', async function() {
      // Allow to transfer tokens
      const tokensToApprove = toGRT('1000')
      const permit = await permitOK(tokensToApprove)
      const tx = createPermitTransaction(permit, me.privateKey)
      await expect(tx)
        .to.emit(grt, 'Approval')
        .withArgs(permit.owner, permit.spender, tokensToApprove)

      // Allowance updated
      const allowance = await grt.allowance(me.address, other.address)
      expect(allowance).to.be.eq(tokensToApprove)

      // Transfer tokens should work
      const tokens = toGRT('100')
      await grt.connect(other).transferFrom(me.address, other.address, tokens)
    })

    it('should permit max token allowance', async function() {
      // Allow to transfer tokens
      const permit = await permitMaxOK()
      const tx = createPermitTransaction(permit, me.privateKey)
      await expect(tx)
        .to.emit(grt, 'Approval')
        .withArgs(permit.owner, permit.spender, MaxUint256)

      // Allowance updated
      const allowance = await grt.allowance(me.address, other.address)
      expect(allowance).to.be.eq(MaxUint256)

      // Transfer tokens should work
      const tokens = toGRT('100')
      await grt.connect(other).transferFrom(me.address, other.address, tokens)
    })

    it('reject to transfer more tokens than approved by permit', async function() {
      // Allow to transfer tokens
      const tokensToApprove = toGRT('1000')
      const permit = await permitOK(tokensToApprove)
      await createPermitTransaction(permit, me.privateKey)

      // Should not transfer more than approved
      const tooManyTokens = toGRT('1001')
      const tx = grt.connect(other).transferFrom(me.address, other.address, tooManyTokens)
      expect(tx).to.be.revertedWith('ERC20: transfer amount exceeds allowance')

      // Should transfer up to the approved amount
      await grt.connect(other).transferFrom(me.address, other.address, tokensToApprove)
    })

    it('reject use two permits with same nonce', async function() {
      // Allow to transfer tokens
      const permit = await permitMaxOK()
      await createPermitTransaction(permit, me.privateKey)

      // Try to re-use the permit
      const tx = createPermitTransaction(permit, me.privateKey)
      await expect(tx).to.revertedWith('GRT: invalid permit')
    })

    it('reject use expired permit', async function() {
      const permit = await permitExpired()
      const tx = createPermitTransaction(permit, me.privateKey)
      await expect(tx).to.revertedWith('GRT: expired permit')
    })

    it('reject permit if holder address does not match', async function() {
      const permit = await permitMaxOK()
      const tx = createPermitTransaction(permit, other.privateKey)
      await expect(tx).to.revertedWith('GRT: invalid permit')
    })

    it('should deny transfer from if permit was denied', async function() {
      // Allow to transfer tokens
      const permit1 = await permitMaxOK()
      await createPermitTransaction(permit1, me.privateKey)

      // Deny transfer tokens
      const permit2 = await permitDeny()
      await createPermitTransaction(permit2, me.privateKey)

      // Allowance updated
      const allowance = await grt.allowance(me.address, other.address)
      expect(allowance).to.be.eq(toBN('0'))

      // Try to transfer without permit should fail
      const tokens = toGRT('100')
      const tx = grt.connect(other).transferFrom(me.address, other.address, tokens)
      await expect(tx).to.revertedWith('ERC20: transfer amount exceeds allowance')
    })
  })

  describe('mint', function() {
    describe('addMinter', function() {
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

    describe('mint', async function() {
      it('reject mint if not minter', async function() {
        const tx = grt.connect(me).mint(me.address, toGRT('100'))
        await expect(tx).to.be.revertedWith('Only minter can call')
      })
    })

    context('> when is minter', function() {
      beforeEach(async function() {
        await grt.connect(governor).addMinter(me.address)
        expect(await grt.isMinter(me.address)).to.be.eq(true)
      })

      describe('mint', async function() {
        it('should mint', async function() {
          const beforeTokens = await grt.balanceOf(me.address)

          const tokensToMint = toGRT('100')
          const tx = grt.connect(me).mint(me.address, tokensToMint)
          await expect(tx)
            .to.emit(grt, 'Transfer')
            .withArgs(AddressZero, me.address, tokensToMint)

          const afterTokens = await grt.balanceOf(me.address)
          expect(afterTokens).to.eq(beforeTokens.add(tokensToMint))
        })

        it('should mint if governor', async function() {
          const tokensToMint = toGRT('100')
          await grt.connect(governor).mint(me.address, tokensToMint)
        })
      })

      describe('removeMinter', function() {
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

      describe('renounceMinter', function() {
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
