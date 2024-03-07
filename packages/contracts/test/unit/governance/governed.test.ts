import { expect } from 'chai'
import hre from 'hardhat'
import '@nomiclabs/hardhat-ethers'

import { Governed } from '../../../build/types/Governed'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

const { ethers } = hre
const { AddressZero } = ethers.constants

describe('Governed', () => {
  const graph = hre.graph()
  let me: SignerWithAddress
  let governor: SignerWithAddress

  let governed: Governed

  beforeEach(async function () {
    [me, governor] = await graph.getTestAccounts()

    const factory = await ethers.getContractFactory('GovernedMock')
    governed = (await factory.connect(governor).deploy()) as Governed
  })

  it('should reject transfer if not allowed', async function () {
    const tx = governed.connect(me).transferOwnership(me.address)
    await expect(tx).revertedWith('Only Governor can call')
  })

  it('should transfer and accept', async function () {
    // Transfer ownership
    const tx1 = governed.connect(governor).transferOwnership(me.address)
    await expect(tx1).emit(governed, 'NewPendingOwnership').withArgs(AddressZero, me.address)

    // Reject accept if not the pending governor
    await expect(governed.connect(governor).acceptOwnership()).revertedWith(
      'Caller must be pending governor',
    )

    // Accept ownership
    const tx2 = governed.connect(me).acceptOwnership()
    await expect(tx2).emit(governed, 'NewOwnership').withArgs(governor.address, me.address)

    // Clean pending governor
    expect(await governed.pendingGovernor()).eq(AddressZero)
  })
})
