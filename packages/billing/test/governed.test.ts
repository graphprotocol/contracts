import { expect } from 'chai'
import hre from 'hardhat'
import '@nomicfoundation/hardhat-chai-matchers'

import { Governed } from '../build/types/contracts/Governed'

import { getAccounts, Account } from '../utils/helpers'

const { ethers } = hre
const { AddressZero } = ethers.constants

describe('Governed', () => {
  let me: Account
  let governor: Account

  let governed: Governed

  beforeEach(async function () {
    // eslint-disable-next-line @typescript-eslint/no-extra-semi
    ;[me, governor] = await getAccounts()

    const factory = await ethers.getContractFactory('Governed')
    governed = (await factory.connect(governor.signer).deploy(governor.address)) as unknown as Governed
  })

  it('should reject deployment if governor is zero', async function () {
    const factory = await ethers.getContractFactory('Governed')
    const unsignedTx = await factory.getDeployTransaction(AddressZero)
    const tx = governor.signer.sendTransaction(unsignedTx)
    await expect(tx).revertedWith('Governor must not be 0')
  })

  it('should reject transfer if not allowed', async function () {
    const tx = governed.connect(me.signer).transferOwnership(me.address)
    await expect(tx).revertedWith('Only Governor can call')
  })

  it('should reject transfer to zero address', async function () {
    // Transfer ownership
    const tx1 = governed.connect(governor.signer).transferOwnership(AddressZero)
    await expect(tx1).rejectedWith('Governor must be set')
  })

  it('should transfer and accept', async function () {
    // Transfer ownership
    const tx1 = governed.connect(governor.signer).transferOwnership(me.address)
    await expect(tx1).emit(governed, 'NewPendingOwnership').withArgs(AddressZero, me.address)

    // Reject accept if not the pending governor
    await expect(governed.connect(governor.signer).acceptOwnership()).revertedWith('Caller must be pending governor')

    // Accept ownership
    const tx2 = governed.connect(me.signer).acceptOwnership()
    await expect(tx2).emit(governed, 'NewOwnership').withArgs(governor.address, me.address)

    // Clean pending governor
    expect(await governed.pendingGovernor()).eq(AddressZero)
  })
})
