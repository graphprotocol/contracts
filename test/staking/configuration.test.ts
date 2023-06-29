import { expect } from 'chai'
import { ethers } from 'hardhat'
import { constants } from 'ethers'

import { IStaking } from '../../build/types/IStaking'

import { defaults, deployContract } from '../lib/deployment'
import { NetworkFixture } from '../lib/fixtures'
import { getAccounts, toBN, toGRT, Account } from '../lib/testHelpers'
import { GraphProxy } from '../../build/types/GraphProxy'
import { GraphProxyAdmin } from '../../build/types/GraphProxyAdmin'
import { network } from '../../cli'

const { AddressZero } = constants

const MAX_PPM = toBN('1000000')

describe('Staking:Config', () => {
  let me: Account
  let other: Account
  let governor: Account
  let slasher: Account

  let fixture: NetworkFixture

  let staking: IStaking
  let proxyAdmin: GraphProxyAdmin

  before(async function () {
    ;[me, other, governor, slasher] = await getAccounts()

    fixture = new NetworkFixture()
    ;({ staking, proxyAdmin } = await fixture.load(governor.signer, slasher.signer))
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('minimumIndexerStake', function () {
    it('should set `minimumIndexerStake`', async function () {
      const oldValue = defaults.staking.minimumIndexerStake
      const newValue = toGRT('100')

      // Set right in the constructor
      expect(await staking.minimumIndexerStake()).eq(oldValue)

      // Set new value
      await staking.connect(governor.signer).setMinimumIndexerStake(newValue)
      expect(await staking.minimumIndexerStake()).eq(newValue)
    })

    it('reject set `minimumIndexerStake` if not allowed', async function () {
      const newValue = toGRT('100')
      const tx = staking.connect(me.signer).setMinimumIndexerStake(newValue)
      await expect(tx).revertedWith('Only Controller governor')
    })

    it('reject set `minimumIndexerStake` to zero', async function () {
      const tx = staking.connect(governor.signer).setMinimumIndexerStake(0)
      await expect(tx).revertedWith('!minimumIndexerStake')
    })
  })

  describe('setSlasher', function () {
    it('should set `slasher`', async function () {
      expect(await staking.slashers(me.address)).eq(false)

      await staking.connect(governor.signer).setSlasher(me.address, true)
      expect(await staking.slashers(me.address)).eq(true)

      await staking.connect(governor.signer).setSlasher(me.address, false)
      expect(await staking.slashers(me.address)).eq(false)
    })

    it('reject set `slasher` if not allowed', async function () {
      const tx = staking.connect(other.signer).setSlasher(me.address, true)
      await expect(tx).revertedWith('Only Controller governor')
    })

    it('reject set `slasher` for zero', async function () {
      const tx = staking.connect(governor.signer).setSlasher(AddressZero, true)
      await expect(tx).revertedWith('!slasher')
    })
  })

  describe('setAssetHolder', function () {
    it('should set `assetHolder`', async function () {
      expect(await staking.assetHolders(me.address)).eq(false)

      const tx1 = staking.connect(governor.signer).setAssetHolder(me.address, true)
      await expect(tx1)
        .emit(staking, 'AssetHolderUpdate')
        .withArgs(governor.address, me.address, true)
      expect(await staking.assetHolders(me.address)).eq(true)

      const tx2 = staking.connect(governor.signer).setAssetHolder(me.address, false)
      await expect(tx2)
        .emit(staking, 'AssetHolderUpdate')
        .withArgs(governor.address, me.address, false)
      await staking.connect(governor.signer).setAssetHolder(me.address, false)
      expect(await staking.assetHolders(me.address)).eq(false)
    })

    it('reject set `assetHolder` if not allowed', async function () {
      const tx = staking.connect(other.signer).setAssetHolder(me.address, true)
      await expect(tx).revertedWith('Only Controller governor')
    })

    it('reject set `assetHolder` to address zero', async function () {
      const tx = staking.connect(governor.signer).setAssetHolder(AddressZero, true)
      await expect(tx).revertedWith('!assetHolder')
    })
  })

  describe('curationPercentage', function () {
    it('should set `curationPercentage`', async function () {
      const newValue = toBN('5')
      await staking.connect(governor.signer).setCurationPercentage(newValue)
      expect(await staking.curationPercentage()).eq(newValue)
    })

    it('reject set `curationPercentage` if out of bounds', async function () {
      const newValue = MAX_PPM.add(toBN('1'))
      const tx = staking.connect(governor.signer).setCurationPercentage(newValue)
      await expect(tx).revertedWith('>percentage')
    })

    it('reject set `curationPercentage` if not allowed', async function () {
      const tx = staking.connect(other.signer).setCurationPercentage(50)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })

  describe('protocolPercentage', function () {
    it('should set `protocolPercentage`', async function () {
      for (const newValue of [toBN('0'), toBN('5'), MAX_PPM]) {
        await staking.connect(governor.signer).setProtocolPercentage(newValue)
        expect(await staking.protocolPercentage()).eq(newValue)
      }
    })

    it('reject set `protocolPercentage` if out of bounds', async function () {
      const newValue = MAX_PPM.add(toBN('1'))
      const tx = staking.connect(governor.signer).setProtocolPercentage(newValue)
      await expect(tx).revertedWith('>percentage')
    })

    it('reject set `protocolPercentage` if not allowed', async function () {
      const tx = staking.connect(other.signer).setProtocolPercentage(50)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })

  describe('maxAllocationEpochs', function () {
    it('should set `maxAllocationEpochs`', async function () {
      const newValue = toBN('5')
      await staking.connect(governor.signer).setMaxAllocationEpochs(newValue)
      expect(await staking.maxAllocationEpochs()).eq(newValue)
    })

    it('reject set `maxAllocationEpochs` if not allowed', async function () {
      const newValue = toBN('5')
      const tx = staking.connect(other.signer).setMaxAllocationEpochs(newValue)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })

  describe('thawingPeriod', function () {
    it('should set `thawingPeriod`', async function () {
      const newValue = toBN('5')
      await staking.connect(governor.signer).setThawingPeriod(newValue)
      expect(await staking.thawingPeriod()).eq(newValue)
    })

    it('reject set `thawingPeriod` if not allowed', async function () {
      const newValue = toBN('5')
      const tx = staking.connect(other.signer).setThawingPeriod(newValue)
      await expect(tx).revertedWith('Only Controller governor')
    })

    it('reject set `thawingPeriod` to zero', async function () {
      const tx = staking.connect(governor.signer).setThawingPeriod(0)
      await expect(tx).revertedWith('!thawingPeriod')
    })
  })

  describe('rebateParameters', function () {
    it('should be setup on init', async function () {
      expect(await staking.alphaNumerator()).eq(toBN(100))
      expect(await staking.alphaDenominator()).eq(toBN(100))
      expect(await staking.lambdaNumerator()).eq(toBN(60))
      expect(await staking.lambdaDenominator()).eq(toBN(100))
    })

    it('should set `rebateParameters`', async function () {
      await staking.connect(governor.signer).setRebateParameters(5, 6, 7, 8)
      expect(await staking.alphaNumerator()).eq(toBN(5))
      expect(await staking.alphaDenominator()).eq(toBN(6))
      expect(await staking.lambdaNumerator()).eq(toBN(7))
      expect(await staking.lambdaDenominator()).eq(toBN(8))
    })

    it('reject set `rebateParameters` if out of bounds', async function () {
      const tx2 = staking.connect(governor.signer).setRebateParameters(1, 0, 1, 1)
      await expect(tx2).revertedWith('!alphaDenominator')

      const tx3 = staking.connect(governor.signer).setRebateParameters(1, 1, 0, 1)
      await expect(tx3).revertedWith('!lambdaNumerator')

      const tx4 = staking.connect(governor.signer).setRebateParameters(1, 1, 1, 0)
      await expect(tx4).revertedWith('!lambdaDenominator')
    })

    it('reject set `rebateParameters` if not allowed', async function () {
      const tx = staking.connect(other.signer).setRebateParameters(1, 1, 1, 1)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })

  describe('Staking and StakingExtension', function () {
    it('does not allow calling the fallback from the Staking implementation', async function () {
      const impl = await proxyAdmin.getProxyImplementation(staking.address)

      const factory = await ethers.getContractFactory('StakingExtension')
      const implAsStaking = factory.attach(impl) as IStaking
      const tx = implAsStaking.connect(other.signer).setDelegationRatio(50)
      await expect(tx).revertedWith('only through proxy')
    })
    it('can set the staking extension implementation with setExtensionImpl', async function () {
      const newImpl = await network.deployContract('StakingExtension', [], governor.signer)
      const tx = await staking.connect(governor.signer).setExtensionImpl(newImpl.contract.address)
      await expect(tx)
        .emit(staking, 'ExtensionImplementationSet')
        .withArgs(newImpl.contract.address)
    })
    it('rejects calls to setExtensionImpl from non-governor', async function () {
      const newImpl = await network.deployContract('StakingExtension', [], governor.signer)
      const tx = staking.connect(other.signer).setExtensionImpl(newImpl.contract.address)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })
})
