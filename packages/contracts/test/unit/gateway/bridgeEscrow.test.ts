import hre from 'hardhat'
import { expect } from 'chai'
import { BigNumber } from 'ethers'

import { GraphToken } from '../../../build/types/GraphToken'
import { BridgeEscrow } from '../../../build/types/BridgeEscrow'

import { NetworkFixture } from '../lib/fixtures'

import { GraphNetworkContracts, toGRT } from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

describe('BridgeEscrow', () => {
  const graph = hre.graph()
  let governor: SignerWithAddress
  let tokenReceiver: SignerWithAddress
  let spender: SignerWithAddress

  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts
  let grt: GraphToken
  let bridgeEscrow: BridgeEscrow

  const nTokens = toGRT('1000')

  before(async function () {
    ;[tokenReceiver, spender] = await graph.getTestAccounts()
    ;({ governor } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
    grt = contracts.GraphToken as GraphToken
    bridgeEscrow = contracts.BridgeEscrow as BridgeEscrow

    // Give some funds to the Escrow
    await grt.connect(governor).mint(bridgeEscrow.address, nTokens)
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('approveAll', function () {
    it('cannot be called by someone other than the governor', async function () {
      const tx = bridgeEscrow.connect(tokenReceiver).approveAll(spender.address)
      await expect(tx).revertedWith('Only Controller governor')
    })
    it('allows a spender to transfer GRT held by the contract', async function () {
      expect(await grt.allowance(bridgeEscrow.address, spender.address)).eq(0)
      const tx = grt
        .connect(spender)
        .transferFrom(bridgeEscrow.address, tokenReceiver.address, nTokens)
      await expect(tx).revertedWith('ERC20: transfer amount exceeds allowance')
      await bridgeEscrow.connect(governor).approveAll(spender.address)
      await expect(
        grt.connect(spender).transferFrom(bridgeEscrow.address, tokenReceiver.address, nTokens),
      ).to.emit(grt, 'Transfer')
      expect(await grt.balanceOf(tokenReceiver.address)).to.eq(nTokens)
    })
  })

  describe('revokeAll', function () {
    it('cannot be called by someone other than the governor', async function () {
      const tx = bridgeEscrow.connect(tokenReceiver).revokeAll(spender.address)
      await expect(tx).revertedWith('Only Controller governor')
    })
    it("revokes a spender's permission to transfer GRT held by the contract", async function () {
      await bridgeEscrow.connect(governor).approveAll(spender.address)
      await bridgeEscrow.connect(governor).revokeAll(spender.address)
      // We shouldn't be able to transfer _anything_
      const tx = grt
        .connect(spender)
        .transferFrom(bridgeEscrow.address, tokenReceiver.address, BigNumber.from('1'))
      await expect(tx).revertedWith('ERC20: transfer amount exceeds allowance')
    })
  })
})
