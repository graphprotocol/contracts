import { expect } from 'chai'
import hre from 'hardhat'
import '@nomiclabs/hardhat-ethers'

import { Governed } from '../../build/types/Governed'

import { getAccounts, Account } from '../lib/testHelpers'

const { ethers } = hre
const { AddressZero } = ethers.constants

describe('Governed', () => {
  let me: Account
  let governor: Account

  let governed: Governed

  beforeEach(async function () {
    ;[me, governor] = await getAccounts()

    const factory = await ethers.getContractFactory('GovernedMock')
    governed = (await factory.connect(governor.signer).deploy()) as unknown as Governed
  })

  it('should reject transfer if not allowed', async function () {
    const tx = governed.connect(me.signer).transferOwnership(me.address)
    await expect(tx).revertedWith('Only Governor can call')
  })

  it('should transfer and accept', async function () {
    // Transfer ownership
    const tx1 = governed.connect(governor.signer).transferOwnership(me.address)
    await expect(tx1).emit(governed, 'NewPendingOwnership').withArgs(AddressZero, me.address)

    // Reject accept if not the pending governor
    await expect(governed.connect(governor.signer).acceptOwnership()).revertedWith(
      'Caller must be pending governor',
    )

    // Accept ownership
    const tx2 = governed.connect(me.signer).acceptOwnership()
    await expect(tx2).emit(governed, 'NewOwnership').withArgs(governor.address, me.address)

    // Clean pending governor
    expect(await governed.pendingGovernor()).eq(AddressZero)
  })
})
