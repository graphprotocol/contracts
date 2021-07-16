import { expect } from 'chai'
import { BigNumber, constants, Wallet } from 'ethers'

import { AllocationExchange } from '../../build/types/AllocationExchange'
import { GraphToken } from '../../build/types/GraphToken'
import { Staking } from '../../build/types/Staking'

import { NetworkFixture } from '../lib/fixtures'
import * as deployment from '../lib/deployment'
import {
  deriveChannelKey,
  getAccounts,
  randomAddress,
  randomHexBytes,
  toGRT,
  Account,
} from '../lib/testHelpers'
import { arrayify, joinSignature, SigningKey, solidityKeccak256 } from 'ethers/lib/utils'

const { AddressZero, MaxUint256 } = constants

interface Voucher {
  allocationID: string
  amount: BigNumber
  signature: string
}

describe('AllocationExchange', () => {
  let governor: Account
  let indexer: Account
  let authority: Wallet

  let fixture: NetworkFixture

  let grt: GraphToken
  let staking: Staking
  let allocationExchange: AllocationExchange

  async function createVoucher(
    allocationID: string,
    amount: BigNumber,
    signerKey: string,
  ): Promise<Voucher> {
    const messageHash = solidityKeccak256(['address', 'uint256'], [allocationID, amount])
    const messageHashBytes = arrayify(messageHash)
    const key = new SigningKey(signerKey)
    const signature = key.signDigest(messageHashBytes)
    return {
      allocationID,
      amount,
      signature: joinSignature(signature),
    }
  }

  before(async function () {
    ;[governor, indexer] = await getAccounts()
    authority = Wallet.createRandom()

    fixture = new NetworkFixture()
    ;({ grt, staking } = await fixture.load(governor.signer))
    allocationExchange = (await deployment.deployContract(
      'AllocationExchange',
      governor.signer,
      grt.address,
      staking.address,
      governor.address,
      authority.address,
    )) as unknown as AllocationExchange

    // Give some funds to the indexer and approve staking contract to use funds on indexer behalf
    const indexerTokens = toGRT('100000')
    await grt.connect(governor.signer).mint(indexer.address, indexerTokens)
    await grt.connect(indexer.signer).approve(staking.address, indexerTokens)

    // Give some funds to the AllocationExchange
    const exchangeTokens = toGRT('2000')
    await grt.connect(governor.signer).mint(allocationExchange.address, exchangeTokens)

    // Ensure the exchange is correctly setup
    await staking.connect(governor.signer).setAssetHolder(allocationExchange.address, true)
    await allocationExchange.connect(governor.signer).setAuthority(authority.address, true)
    await allocationExchange.approveAll()
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  async function setupAllocation(): Promise<string> {
    // Generate test data
    const channelKey = deriveChannelKey()
    const allocationID = channelKey.address
    const subgraphDeploymentID = randomHexBytes(32)
    const metadata = randomHexBytes(32)

    // Setup staking
    const stakeTokens = toGRT('100000')
    await staking.connect(indexer.signer).stake(stakeTokens)
    await staking
      .connect(indexer.signer)
      .allocate(
        subgraphDeploymentID,
        stakeTokens,
        allocationID,
        metadata,
        await channelKey.generateProof(indexer.address),
      )
    return allocationID
  }

  describe('config', function () {
    it('should set an authority', async function () {
      // Set authority
      const newAuthority = randomAddress()
      const tx1 = allocationExchange.connect(governor.signer).setAuthority(newAuthority, true)
      await expect(tx1).emit(allocationExchange, 'AuthoritySet').withArgs(newAuthority, true)
      expect(await allocationExchange.authority(newAuthority)).eq(true)

      // Unset authority
      const tx2 = allocationExchange.connect(governor.signer).setAuthority(newAuthority, false)
      await expect(tx2).emit(allocationExchange, 'AuthoritySet').withArgs(newAuthority, false)
      expect(await allocationExchange.authority(newAuthority)).eq(false)
    })

    it('reject set an authority if not allowed', async function () {
      const newAuthority = randomAddress()
      const tx = allocationExchange.connect(indexer.signer).setAuthority(newAuthority, true)
      await expect(tx).revertedWith(' Only Governor can call')
    })

    it('reject set an empty authority', async function () {
      const newAuthority = AddressZero
      const tx = allocationExchange.connect(governor.signer).setAuthority(newAuthority, true)
      await expect(tx).revertedWith('Exchange: empty authority')
    })

    it('should allow to approve all tokens to staking contract', async function () {
      await allocationExchange.approveAll()
      const allowance = await grt.allowance(allocationExchange.address, staking.address)
      expect(allowance).eq(MaxUint256)
    })
  })

  describe('withdraw funds', function () {
    it('should withdraw to destination', async function () {
      const beforeExchangeBalance = await grt.balanceOf(allocationExchange.address)

      const destinationAddress = randomAddress()
      const amount = toGRT('1000')
      const tx = allocationExchange.connect(governor.signer).withdraw(destinationAddress, amount)
      await expect(tx)
        .emit(allocationExchange, 'TokensWithdrawn')
        .withArgs(destinationAddress, amount)

      const afterExchangeBalance = await grt.balanceOf(allocationExchange.address)
      const afterDestinationBalance = await grt.balanceOf(destinationAddress)

      expect(afterExchangeBalance).eq(beforeExchangeBalance.sub(amount))
      expect(afterDestinationBalance).eq(amount)
    })

    it('reject withdraw zero amount', async function () {
      const destinationAddress = randomAddress()
      const amount = toGRT('0')
      const tx = allocationExchange.connect(governor.signer).withdraw(destinationAddress, amount)
      await expect(tx).revertedWith('Exchange: empty amount')
    })

    it('reject withdraw to zero destination', async function () {
      const destinationAddress = AddressZero
      const amount = toGRT('1000')
      const tx = allocationExchange.connect(governor.signer).withdraw(destinationAddress, amount)
      await expect(tx).revertedWith('Exchange: empty destination')
    })

    it('reject withdraw if not allowed', async function () {
      const destinationAddress = randomAddress()
      const amount = toGRT('1000')
      const tx = allocationExchange.connect(indexer.address).withdraw(destinationAddress, amount)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('redeem vouchers', function () {
    it('redeem a voucher', async function () {
      const beforeExchangeBalance = await grt.balanceOf(allocationExchange.address)

      // Setup an active allocation
      const allocationID = await setupAllocation()

      // Initiate a withdrawal
      const actualAmount = toGRT('2000') // <- withdraw amount
      const voucher = await createVoucher(allocationID, actualAmount, authority.privateKey)
      const tx = allocationExchange.redeem(voucher)
      await expect(tx)
        .emit(allocationExchange, 'AllocationRedeemed')
        .withArgs(allocationID, actualAmount)

      // Allocation must have collected the withdrawn tokens
      const allocation = await staking.allocations(allocationID)
      expect(allocation.collectedFees).eq(actualAmount)

      // AllocationExchange should have less funds
      const afterExchangeBalance = await grt.balanceOf(allocationExchange.address)
      expect(afterExchangeBalance).eq(beforeExchangeBalance.sub(actualAmount))
    })

    it('reject double spending of a voucher', async function () {
      // Setup an active allocation
      const allocationID = await setupAllocation()

      // Initiate a withdrawal
      const actualAmount = toGRT('2000') // <- withdraw amount
      const voucher = await createVoucher(allocationID, actualAmount, authority.privateKey)

      // First redeem
      await allocationExchange.redeem(voucher)

      // Double spend the same voucher!
      await expect(allocationExchange.redeem(voucher)).revertedWith(
        'Exchange: allocation already redeemed',
      )
    })

    it('reject redeem voucher for invalid allocation', async function () {
      // Use an invalid allocation
      const allocationID = '0xfefefefefefefefefefefefefefefefefefefefe'

      // Ensure the exchange is correctly setup
      await allocationExchange.connect(governor.signer).setAuthority(authority.address, true)
      await allocationExchange.approveAll()

      // Initiate a withdrawal
      const actualAmount = toGRT('2000') // <- withdraw amount
      const voucher = await createVoucher(allocationID, actualAmount, authority.privateKey)
      const tx = allocationExchange.redeem(voucher)
      await expect(tx).revertedWith('!collect')
    })

    it('reject redeem voucher not signed by the authority', async function () {
      // Initiate a withdrawal
      const actualAmount = toGRT('2000') // <- withdraw amount
      const voucher = await createVoucher(
        randomAddress(),
        actualAmount,
        Wallet.createRandom().privateKey, // <-- signed by anon
      )
      const tx = allocationExchange.redeem(voucher)
      await expect(tx).revertedWith('Exchange: invalid signer')
    })

    it('reject redeem voucher with empty amount', async function () {
      // Initiate a withdrawal
      const actualAmount = toGRT('0') // <- withdraw amount
      const voucher = await createVoucher(randomAddress(), actualAmount, authority.privateKey)
      const tx = allocationExchange.redeem(voucher)
      await expect(tx).revertedWith('Exchange: zero tokens voucher')
    })

    it('reject redeem voucher with invalid signature', async function () {
      const actualAmount = toGRT('2000') // <- withdraw amount
      const voucher = await createVoucher(randomAddress(), actualAmount, authority.privateKey)
      voucher.signature = '0x1234'
      const tx = allocationExchange.redeem(voucher)
      await expect(tx).revertedWith('Exchange: invalid signature')
    })
  })
})
