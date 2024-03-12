import hre from 'hardhat'
import { expect } from 'chai'
import { ethers } from 'hardhat'
import { constants } from 'ethers'

import { IStaking } from '../../../build/types/IStaking'

import { NetworkFixture } from '../lib/fixtures'
import { GraphProxyAdmin } from '../../../build/types/GraphProxyAdmin'
import { deploy, DeployType, GraphNetworkContracts, toBN, toGRT } from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

const { AddressZero } = constants

const MAX_PPM = toBN('1000000')

describe('Staking:Config', () => {
  const graph = hre.graph()

  let me: SignerWithAddress
  let other: SignerWithAddress
  let governor: SignerWithAddress

  let fixture: NetworkFixture

  let contracts: GraphNetworkContracts
  let staking: IStaking
  let proxyAdmin: GraphProxyAdmin

  before(async function () {
    [me, other] = await graph.getTestAccounts()
    ;({ governor } = await graph.getNamedAccounts())

    fixture = new NetworkFixture(graph.provider)
    contracts = await fixture.load(governor)
    staking = contracts.Staking as IStaking
    proxyAdmin = contracts.GraphProxyAdmin
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  describe('minimumIndexerStake', function () {
    it('should set `minimumIndexerStake`', async function () {
      const oldValue = toGRT('10')
      const newValue = toGRT('100')

      // Set right in the constructor
      expect(await staking.minimumIndexerStake()).eq(oldValue)

      // Set new value
      await staking.connect(governor).setMinimumIndexerStake(newValue)
      expect(await staking.minimumIndexerStake()).eq(newValue)
    })

    it('reject set `minimumIndexerStake` if not allowed', async function () {
      const newValue = toGRT('100')
      const tx = staking.connect(me).setMinimumIndexerStake(newValue)
      await expect(tx).revertedWith('Only Controller governor')
    })

    it('reject set `minimumIndexerStake` to zero', async function () {
      const tx = staking.connect(governor).setMinimumIndexerStake(0)
      await expect(tx).revertedWith('!minimumIndexerStake')
    })
  })

  describe('setSlasher', function () {
    it('should set `slasher`', async function () {
      expect(await staking.slashers(me.address)).eq(false)

      await staking.connect(governor).setSlasher(me.address, true)
      expect(await staking.slashers(me.address)).eq(true)

      await staking.connect(governor).setSlasher(me.address, false)
      expect(await staking.slashers(me.address)).eq(false)
    })

    it('reject set `slasher` if not allowed', async function () {
      const tx = staking.connect(other).setSlasher(me.address, true)
      await expect(tx).revertedWith('Only Controller governor')
    })

    it('reject set `slasher` for zero', async function () {
      const tx = staking.connect(governor).setSlasher(AddressZero, true)
      await expect(tx).revertedWith('!slasher')
    })
  })

  describe('curationPercentage', function () {
    it('should set `curationPercentage`', async function () {
      const newValue = toBN('5')
      await staking.connect(governor).setCurationPercentage(newValue)
      expect(await staking.curationPercentage()).eq(newValue)
    })

    it('reject set `curationPercentage` if out of bounds', async function () {
      const newValue = MAX_PPM.add(toBN('1'))
      const tx = staking.connect(governor).setCurationPercentage(newValue)
      await expect(tx).revertedWith('>percentage')
    })

    it('reject set `curationPercentage` if not allowed', async function () {
      const tx = staking.connect(other).setCurationPercentage(50)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })

  describe('protocolPercentage', function () {
    it('should set `protocolPercentage`', async function () {
      for (const newValue of [toBN('0'), toBN('5'), MAX_PPM]) {
        await staking.connect(governor).setProtocolPercentage(newValue)
        expect(await staking.protocolPercentage()).eq(newValue)
      }
    })

    it('reject set `protocolPercentage` if out of bounds', async function () {
      const newValue = MAX_PPM.add(toBN('1'))
      const tx = staking.connect(governor).setProtocolPercentage(newValue)
      await expect(tx).revertedWith('>percentage')
    })

    it('reject set `protocolPercentage` if not allowed', async function () {
      const tx = staking.connect(other).setProtocolPercentage(50)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })

  describe('maxAllocationEpochs', function () {
    it('should set `maxAllocationEpochs`', async function () {
      const newValue = toBN('5')
      await staking.connect(governor).setMaxAllocationEpochs(newValue)
      expect(await staking.maxAllocationEpochs()).eq(newValue)
    })

    it('reject set `maxAllocationEpochs` if not allowed', async function () {
      const newValue = toBN('5')
      const tx = staking.connect(other).setMaxAllocationEpochs(newValue)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })

  describe('thawingPeriod', function () {
    it('should set `thawingPeriod`', async function () {
      const newValue = toBN('5')
      await staking.connect(governor).setThawingPeriod(newValue)
      expect(await staking.thawingPeriod()).eq(newValue)
    })

    it('reject set `thawingPeriod` if not allowed', async function () {
      const newValue = toBN('5')
      const tx = staking.connect(other).setThawingPeriod(newValue)
      await expect(tx).revertedWith('Only Controller governor')
    })

    it('reject set `thawingPeriod` to zero', async function () {
      const tx = staking.connect(governor).setThawingPeriod(0)
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
      await staking.connect(governor).setRebateParameters(5, 6, 7, 8)
      expect(await staking.alphaNumerator()).eq(toBN(5))
      expect(await staking.alphaDenominator()).eq(toBN(6))
      expect(await staking.lambdaNumerator()).eq(toBN(7))
      expect(await staking.lambdaDenominator()).eq(toBN(8))
    })

    it('reject set `rebateParameters` if out of bounds', async function () {
      const tx2 = staking.connect(governor).setRebateParameters(1, 0, 1, 1)
      await expect(tx2).revertedWith('!alphaDenominator')

      const tx3 = staking.connect(governor).setRebateParameters(1, 1, 0, 1)
      await expect(tx3).revertedWith('!lambdaNumerator')

      const tx4 = staking.connect(governor).setRebateParameters(1, 1, 1, 0)
      await expect(tx4).revertedWith('!lambdaDenominator')
    })

    it('reject set `rebateParameters` if not allowed', async function () {
      const tx = staking.connect(other).setRebateParameters(1, 1, 1, 1)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })

  describe('Staking and StakingExtension', function () {
    it('does not allow calling the fallback from the Staking implementation', async function () {
      const impl = await proxyAdmin.getProxyImplementation(staking.address)

      const factory = await ethers.getContractFactory('StakingExtension')
      const implAsStaking = factory.attach(impl) as IStaking
      const tx = implAsStaking.connect(other).setDelegationRatio(50)
      await expect(tx).revertedWith('only through proxy')
    })
    it('can set the staking extension implementation with setExtensionImpl', async function () {
      const newImpl = await deploy(DeployType.Deploy, governor, {
        name: 'StakingExtension',
      })
      const tx = await staking.connect(governor).setExtensionImpl(newImpl.contract.address)
      await expect(tx)
        .emit(staking, 'ExtensionImplementationSet')
        .withArgs(newImpl.contract.address)
    })
    it('rejects calls to setExtensionImpl from non-governor', async function () {
      const newImpl = await deploy(DeployType.Deploy, governor, { name: 'StakingExtension' })
      const tx = staking.connect(other).setExtensionImpl(newImpl.contract.address)
      await expect(tx).revertedWith('Only Controller governor')
    })
  })
})
