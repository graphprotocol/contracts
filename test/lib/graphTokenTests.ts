import { expect } from 'chai'
import { constants, utils, BytesLike, BigNumber, Signature } from 'ethers'
import { eip712 } from '@graphprotocol/common-ts/dist/attestations'

import * as deployment from './deployment'
import { getAccounts, getChainID, toBN, toGRT, Account, initNetwork } from './testHelpers'

import { L2GraphToken } from '../../build/types/L2GraphToken'
import { GraphToken } from '../../build/types/GraphToken'

const { AddressZero, MaxUint256 } = constants
const { keccak256, SigningKey } = utils

const PERMIT_TYPE_HASH = eip712.typeHash(
  'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)',
)
const L1SALT = '0x51f3d585afe6dfeb2af01bba0889a36c1db03beec88c6a4d0c53817069026afa'
const L2SALT = '0xe33842a7acd1d5a1d28f25a931703e5605152dc48d64dc4716efdae1f5659591'

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
  salt: string,
): Signature {
  const domainSeparator = eip712.domainSeparator({
    name: 'Graph Token',
    version: '0',
    chainId,
    verifyingContract: contractAddress,
    salt: salt,
  })
  const hashEncodedPermit = hashEncodePermit(permit)
  const message = eip712.encode(domainSeparator, hashEncodedPermit)
  const messageHash = keccak256(message)
  const signingKey = new SigningKey(signer)
  return signingKey.signDigest(messageHash)
}

export function grtTests(isL2: boolean): void {
  let me: Account
  let other: Account
  let governor: Account
  let salt: string

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
    const chainID = await getChainID()
    const signature: Signature = signPermit(signer, chainID, grt.address, permit, salt)
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

  before(async function () {
    await initNetwork()
    ;[me, other, governor] = await getAccounts()
  })

  beforeEach(async function () {
    // Deploy graph token
    if (isL2) {
      const proxyAdmin = await deployment.deployProxyAdmin(governor.signer)
      grt = await deployment.deployL2GRT(governor.signer, proxyAdmin)
      salt = L2SALT
    } else {
      grt = await deployment.deployGRT(governor.signer)
      salt = L1SALT
    }

    // Mint some tokens
    const tokens = toGRT('10000')
    await grt.connect(governor.signer).mint(me.address, tokens)
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
      await grt.connect(other.signer).transferFrom(me.address, other.address, tokens)
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
      await grt.connect(other.signer).transferFrom(me.address, other.address, tokens)
    })

    it('reject to transfer more tokens than approved by permit', async function () {
      // Allow to transfer tokens
      const tokensToApprove = toGRT('1000')
      const permit = await permitOK(tokensToApprove)
      await createPermitTransaction(permit, mePrivateKey, salt)

      // Should not transfer more than approved
      const tooManyTokens = toGRT('1001')
      const tx = grt.connect(other.signer).transferFrom(me.address, other.address, tooManyTokens)
      await expect(tx).revertedWith('ERC20: transfer amount exceeds allowance')

      // Should transfer up to the approved amount
      await grt.connect(other.signer).transferFrom(me.address, other.address, tokensToApprove)
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
      const tx = grt.connect(other.signer).transferFrom(me.address, other.address, tokens)
      await expect(tx).revertedWith('ERC20: transfer amount exceeds allowance')
    })
  })

  describe('mint', function () {
    describe('addMinter', function () {
      it('reject add a new minter if not allowed', async function () {
        const tx = grt.connect(me.signer).addMinter(me.address)
        await expect(tx).revertedWith('Only Governor can call')
      })

      it('should add a new minter', async function () {
        expect(await grt.isMinter(me.address)).eq(false)
        const tx = grt.connect(governor.signer).addMinter(me.address)
        await expect(tx).emit(grt, 'MinterAdded').withArgs(me.address)
        expect(await grt.isMinter(me.address)).eq(true)
      })
    })

    describe('mint', async function () {
      it('reject mint if not minter', async function () {
        const tx = grt.connect(me.signer).mint(me.address, toGRT('100'))
        await expect(tx).revertedWith('Only minter can call')
      })
    })

    context('> when is minter', function () {
      beforeEach(async function () {
        await grt.connect(governor.signer).addMinter(me.address)
        expect(await grt.isMinter(me.address)).eq(true)
      })

      describe('mint', async function () {
        it('should mint', async function () {
          const beforeTokens = await grt.balanceOf(me.address)

          const tokensToMint = toGRT('100')
          const tx = grt.connect(me.signer).mint(me.address, tokensToMint)
          await expect(tx).emit(grt, 'Transfer').withArgs(AddressZero, me.address, tokensToMint)

          const afterTokens = await grt.balanceOf(me.address)
          expect(afterTokens).eq(beforeTokens.add(tokensToMint))
        })

        it('should mint if governor', async function () {
          const tokensToMint = toGRT('100')
          await grt.connect(governor.signer).mint(me.address, tokensToMint)
        })
      })

      describe('removeMinter', function () {
        it('reject remove a minter if not allowed', async function () {
          const tx = grt.connect(me.signer).removeMinter(me.address)
          await expect(tx).revertedWith('Only Governor can call')
        })

        it('should remove a minter', async function () {
          const tx = grt.connect(governor.signer).removeMinter(me.address)
          await expect(tx).emit(grt, 'MinterRemoved').withArgs(me.address)
          expect(await grt.isMinter(me.address)).eq(false)
        })
      })

      describe('renounceMinter', function () {
        it('should renounce to be a minter', async function () {
          const tx = grt.connect(me.signer).renounceMinter()
          await expect(tx).emit(grt, 'MinterRemoved').withArgs(me.address)
          expect(await grt.isMinter(me.address)).eq(false)
        })
      })
    })
  })
}
