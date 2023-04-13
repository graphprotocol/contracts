import { expect } from 'chai'
import { constants, BigNumber, Event } from 'ethers'
import { defaultAbiCoder, ParamType, parseEther } from 'ethers/lib/utils'

import { GraphToken } from '../../build/types/GraphToken'
import { IL1Staking } from '../../build/types/IL1Staking'
import { IStaking } from '../../build/types/IStaking'
import { L1GraphTokenGateway } from '../../build/types/L1GraphTokenGateway'
import { L1GraphTokenLockMigratorMock } from '../../build/types/L1GraphTokenLockMigratorMock'

import { ArbitrumL1Mocks, L1FixtureContracts, NetworkFixture } from '../lib/fixtures'

import {
  advanceBlockTo,
  deriveChannelKey,
  getAccounts,
  randomHexBytes,
  latestBlock,
  toBN,
  toGRT,
  provider,
  Account,
  setAccountBalance,
  impersonateAccount,
} from '../lib/testHelpers'
import { deployContract } from '../lib/deployment'

const { AddressZero, MaxUint256 } = constants

describe('L1Staking:Migration', () => {
  let me: Account
  let governor: Account
  let indexer: Account
  let slasher: Account
  let l2Indexer: Account
  let delegator: Account
  let l2Delegator: Account
  let mockRouter: Account
  let mockL2GRT: Account
  let mockL2Gateway: Account
  let mockL2GNS: Account
  let mockL2Staking: Account

  let fixture: NetworkFixture
  let fixtureContracts: L1FixtureContracts

  let grt: GraphToken
  let staking: IL1Staking
  let l1GraphTokenGateway: L1GraphTokenGateway
  let arbitrumMocks: ArbitrumL1Mocks
  let l1GraphTokenLockMigrator: L1GraphTokenLockMigratorMock

  // Test values
  const indexerTokens = toGRT('10000000')
  const delegatorTokens = toGRT('1000000')
  const tokensToStake = toGRT('200000')
  const subgraphDeploymentID = randomHexBytes()
  const channelKey = deriveChannelKey()
  const allocationID = channelKey.address
  const metadata = randomHexBytes(32)
  const minimumIndexerStake = toGRT('100000')
  const delegationTaxPPM = 10000 // 1%
  // Dummy L2 gas values
  const maxGas = toBN('1000000')
  const gasPriceBid = toBN('1000000000')
  const maxSubmissionCost = toBN('1000000000')

  // Allocate with test values
  const allocate = async (tokens: BigNumber) => {
    return staking
      .connect(indexer.signer)
      .allocateFrom(
        indexer.address,
        subgraphDeploymentID,
        tokens,
        allocationID,
        metadata,
        await channelKey.generateProof(indexer.address),
      )
  }

  before(async function () {
    ;[
      me,
      governor,
      indexer,
      slasher,
      delegator,
      l2Indexer,
      mockRouter,
      mockL2GRT,
      mockL2Gateway,
      mockL2GNS,
      mockL2Staking,
      l2Delegator,
    ] = await getAccounts()

    fixture = new NetworkFixture()
    fixtureContracts = await fixture.load(governor.signer, slasher.signer)
    ;({ grt, staking, l1GraphTokenGateway } = fixtureContracts)
    // Dummy code on the mock router so that it appears as a contract
    await provider().send('hardhat_setCode', [mockRouter.address, '0x1234'])
    arbitrumMocks = await fixture.loadArbitrumL1Mocks(governor.signer)
    await fixture.configureL1Bridge(
      governor.signer,
      arbitrumMocks,
      fixtureContracts,
      mockRouter.address,
      mockL2GRT.address,
      mockL2Gateway.address,
      mockL2GNS.address,
      mockL2Staking.address,
    )

    l1GraphTokenLockMigrator = (await deployContract(
      'L1GraphTokenLockMigratorMock',
      governor.signer,
    )) as unknown as L1GraphTokenLockMigratorMock

    await setAccountBalance(l1GraphTokenLockMigrator.address, parseEther('1'))

    await staking
      .connect(governor.signer)
      .setL1GraphTokenLockMigrator(l1GraphTokenLockMigrator.address)

    // Give some funds to the indexer and approve staking contract to use funds on indexer behalf
    await grt.connect(governor.signer).mint(indexer.address, indexerTokens)
    await grt.connect(indexer.signer).approve(staking.address, indexerTokens)

    await grt.connect(governor.signer).mint(delegator.address, delegatorTokens)
    await grt.connect(delegator.signer).approve(staking.address, delegatorTokens)

    await staking.connect(governor.signer).setMinimumIndexerStake(minimumIndexerStake)
    await staking.connect(governor.signer).setDelegationTaxPercentage(delegationTaxPPM) // 1%
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  context('> when not staked', function () {
    describe('migrateStakeToL2', function () {
      it('should not allow migrating for someone who has not staked', async function () {
        const tx = staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            tokensToStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('tokensStaked == 0')
      })
    })
  })

  context('> when staked', function () {
    const shouldMigrateIndexerStake = async (
      amountToSend: BigNumber,
      options: {
        expectedSeqNum?: number
        l2Beneficiary?: string
      } = {},
    ) => {
      const l2Beneficiary = options.l2Beneficiary ?? l2Indexer.address
      const expectedSeqNum = options.expectedSeqNum ?? 1
      const tx = staking
        .connect(indexer.signer)
        .migrateStakeToL2(l2Beneficiary, amountToSend, maxGas, gasPriceBid, maxSubmissionCost, {
          value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
        })
      const expectedFunctionData = defaultAbiCoder.encode(['tuple(address)'], [[l2Indexer.address]])

      const expectedCallhookData = defaultAbiCoder.encode(
        ['uint8', 'bytes'],
        [toBN(0), expectedFunctionData], // code = 1 means RECEIVE_INDEXER_CODE
      )
      const expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
        grt.address,
        staking.address,
        mockL2Staking.address,
        amountToSend,
        expectedCallhookData,
      )

      await expect(tx)
        .emit(l1GraphTokenGateway, 'TxToL2')
        .withArgs(staking.address, mockL2Gateway.address, toBN(expectedSeqNum), expectedL2Data)
    }

    beforeEach(async function () {
      await staking.connect(indexer.signer).stake(tokensToStake)
    })

    describe('receive()', function () {
      it('should not allow receiving funds from a random address', async function () {
        const tx = indexer.signer.sendTransaction({
          to: staking.address,
          value: parseEther('1'),
        })
        await expect(tx).revertedWith('Only migrator can send ETH')
      })
      it('should allow receiving funds from the migrator', async function () {
        const impersonatedMigrator = await impersonateAccount(l1GraphTokenLockMigrator.address)
        const tx = impersonatedMigrator.sendTransaction({
          to: staking.address,
          value: parseEther('1'),
        })
        await expect(tx).to.not.be.reverted
      })
    })
    describe('migrateStakeToL2', function () {
      it('should not allow migrating but leaving less than the minimum indexer stake', async function () {
        const tx = staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            tokensToStake.sub(minimumIndexerStake).add(1),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('!minimumIndexerStake remaining')
      })
      it('should not allow migrating less than the minimum indexer stake the first time', async function () {
        const tx = staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            minimumIndexerStake.sub(1),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('!minimumIndexerStake sent')
      })
      it('should not allow migrating if there are tokens locked for withdrawal', async function () {
        await staking.connect(indexer.signer).unstake(tokensToStake)
        const tx = staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            tokensToStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('tokensLocked != 0')
      })
      it('should not allow migrating to a beneficiary that is address zero', async function () {
        const tx = staking
          .connect(indexer.signer)
          .migrateStakeToL2(AddressZero, tokensToStake, maxGas, gasPriceBid, maxSubmissionCost, {
            value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
          })
        await expect(tx).revertedWith('l2Beneficiary == 0')
      })
      it('should not allow migrating the whole stake if there are open allocations', async function () {
        await allocate(toGRT('10'))
        const tx = staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            tokensToStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('allocated')
      })
      it('should not allow migrating partial stake if the remaining indexer capacity is insufficient for open allocations', async function () {
        // We set delegation ratio == 1 so an indexer can only use as much delegation as their own stake
        await staking.connect(governor.signer).setDelegationRatio(1)
        const tokensToDelegate = toGRT('202100')
        await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)

        // Now the indexer has 200k tokens staked and 200k tokens delegated
        await allocate(toGRT('400000'))

        // But if we try to migrate even 100k, we will not have enough indexer capacity to cover the open allocation
        const tx = staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            toGRT('100000'),
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('! allocation capacity')
      })
      it('should not allow migrating if the ETH sent is more than required', async function () {
        const tx = staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            indexer.address,
            tokensToStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)).add(1),
            },
          )
        await expect(tx).revertedWith('INVALID_ETH_AMOUNT')
      })
      it('sends the tokens and a message through the L1GraphTokenGateway', async function () {
        const amountToSend = minimumIndexerStake
        await shouldMigrateIndexerStake(amountToSend)
        // Check that the indexer stake was reduced by the sent amount
        expect((await staking.stakes(indexer.address)).tokensStaked).to.equal(
          tokensToStake.sub(amountToSend),
        )
      })
      it('should allow migrating the whole stake if there are no open allocations', async function () {
        await shouldMigrateIndexerStake(tokensToStake)
        // Check that the indexer stake was reduced by the sent amount
        expect((await staking.stakes(indexer.address)).tokensStaked).to.equal(0)
      })
      it('should allow migrating partial stake if the remaining capacity can cover the allocations', async function () {
        // We set delegation ratio == 1 so an indexer can only use as much delegation as their own stake
        await staking.connect(governor.signer).setDelegationRatio(1)
        const tokensToDelegate = toGRT('200000')
        await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)

        // Now the indexer has 200k tokens staked and 200k tokens delegated,
        // but they allocate 200k
        await allocate(toGRT('200000'))

        // If we migrate 100k, we will still have enough indexer capacity to cover the open allocation
        const amountToSend = toGRT('100000')
        await shouldMigrateIndexerStake(amountToSend)
        // Check that the indexer stake was reduced by the sent amount
        expect((await staking.stakes(indexer.address)).tokensStaked).to.equal(
          tokensToStake.sub(amountToSend),
        )
      })
      it('allows migrating several times to the same beneficiary', async function () {
        // Stake a bit more so we're still over the minimum stake after migrating twice
        await staking.connect(indexer.signer).stake(tokensToStake)
        await shouldMigrateIndexerStake(minimumIndexerStake)
        await shouldMigrateIndexerStake(toGRT('1000'), { expectedSeqNum: 2 })
        expect((await staking.stakes(indexer.address)).tokensStaked).to.equal(
          tokensToStake.mul(2).sub(minimumIndexerStake).sub(toGRT('1000')),
        )
      })
      it('should not allow migrating to a different beneficiary the second time', async function () {
        await shouldMigrateIndexerStake(minimumIndexerStake)
        const tx = staking.connect(indexer.signer).migrateStakeToL2(
          indexer.address, // Note this is different from l2Indexer used before
          minimumIndexerStake,
          maxGas,
          gasPriceBid,
          maxSubmissionCost,
          {
            value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
          },
        )
        await expect(tx).revertedWith('l2Beneficiary != previous')
      })
    })

    describe('migrateLockedStakeToL2', function () {
      it('sends a message through L1GraphTokenGateway like migrateStakeToL2, but gets the beneficiary and ETH from a migrator contract', async function () {
        const amountToSend = minimumIndexerStake

        await l1GraphTokenLockMigrator.setMigratedAddress(indexer.address, l2Indexer.address)
        const oldMigratorEthBalance = await provider().getBalance(l1GraphTokenLockMigrator.address)
        const tx = staking
          .connect(indexer.signer)
          .migrateLockedStakeToL2(minimumIndexerStake, maxGas, gasPriceBid, maxSubmissionCost)
        const expectedFunctionData = defaultAbiCoder.encode(
          ['tuple(address)'],
          [[l2Indexer.address]],
        )

        const expectedCallhookData = defaultAbiCoder.encode(
          ['uint8', 'bytes'],
          [toBN(0), expectedFunctionData], // code = 0 means RECEIVE_INDEXER_CODE
        )
        const expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
          grt.address,
          staking.address,
          mockL2Staking.address,
          amountToSend,
          expectedCallhookData,
        )

        await expect(tx)
          .emit(l1GraphTokenGateway, 'TxToL2')
          .withArgs(staking.address, mockL2Gateway.address, toBN(1), expectedL2Data)
        expect(await provider().getBalance(l1GraphTokenLockMigrator.address)).to.equal(
          oldMigratorEthBalance.sub(maxSubmissionCost).sub(gasPriceBid.mul(maxGas)),
        )
      })
      it('should not allow migrating if the migrator contract returns a zero address beneficiary', async function () {
        const amountToSend = minimumIndexerStake

        const tx = staking
          .connect(indexer.signer)
          .migrateLockedStakeToL2(minimumIndexerStake, maxGas, gasPriceBid, maxSubmissionCost)
        await expect(tx).revertedWith('LOCK NOT MIGRATED')
      })
    })
    describe('unlockDelegationToMigratedIndexer', function () {
      beforeEach(async function () {
        await staking.connect(governor.signer).setDelegationUnbondingPeriod(28) // epochs
      })
      it('allows a delegator to a migrated indexer to withdraw locked delegation before the unbonding period', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)
        const actualDelegation = tokensToDelegate.sub(
          tokensToDelegate.mul(delegationTaxPPM).div(1000000),
        )
        await staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            tokensToStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await staking.connect(delegator.signer).undelegate(indexer.address, actualDelegation)
        const tx = await staking
          .connect(delegator.signer)
          .unlockDelegationToMigratedIndexer(indexer.address)
        await expect(tx)
          .emit(staking, 'StakeDelegatedUnlockedDueToMigration')
          .withArgs(indexer.address, delegator.address)
        const tx2 = await staking
          .connect(delegator.signer)
          .withdrawDelegated(indexer.address, AddressZero)
        await expect(tx2)
          .emit(staking, 'StakeDelegatedWithdrawn')
          .withArgs(indexer.address, delegator.address, actualDelegation)
      })
      it('rejects calls if the indexer has not migrated their stake', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)
        const tx = staking
          .connect(delegator.signer)
          .unlockDelegationToMigratedIndexer(indexer.address)
        await expect(tx).revertedWith('indexer not migrated')
      })
      it('rejects calls if the indexer has only migrated part of their stake but not all', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)
        await staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        const tx = staking
          .connect(delegator.signer)
          .unlockDelegationToMigratedIndexer(indexer.address)
        await expect(tx).revertedWith('indexer not migrated')
      })
      it('rejects calls if the delegator has not undelegated first', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)
        await staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            tokensToStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        const tx = staking
          .connect(delegator.signer)
          .unlockDelegationToMigratedIndexer(indexer.address)
        await expect(tx).revertedWith('! locked')
      })
      it('rejects calls if the caller is not a delegator', async function () {
        await staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            tokensToStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        const tx = staking
          .connect(delegator.signer)
          .unlockDelegationToMigratedIndexer(indexer.address)
        // The function checks for tokensLockedUntil so this is the error we should get:
        await expect(tx).revertedWith('! locked')
      })
    })
    describe('migrateDelegationToL2', function () {
      it('rejects calls if the delegated indexer has not migrated stake to L2', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)

        const tx = staking
          .connect(delegator.signer)
          .migrateDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('indexer not migrated')
      })
      it('rejects calls if the beneficiary is zero', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)
        await staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        const tx = staking
          .connect(delegator.signer)
          .migrateDelegationToL2(
            indexer.address,
            AddressZero,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('l2Beneficiary == 0')
      })
      it('rejects calls if the delegator has tokens locked for undelegation', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)
        await staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await staking.connect(delegator.signer).undelegate(indexer.address, toGRT('1'))

        const tx = staking
          .connect(delegator.signer)
          .migrateDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('tokensLocked != 0')
      })
      it('rejects calls if the delegator has no tokens delegated to the indexer', async function () {
        await staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        const tx = staking
          .connect(delegator.signer)
          .migrateDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('delegation == 0')
      })
      it('sends all the tokens delegated to the indexer to the beneficiary on L2, using the gateway', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)
        const actualDelegation = tokensToDelegate.sub(
          tokensToDelegate.mul(delegationTaxPPM).div(1000000),
        )
        await staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        const expectedFunctionData = defaultAbiCoder.encode(
          ['tuple(address,address)'],
          [[l2Indexer.address, l2Delegator.address]],
        )

        const expectedCallhookData = defaultAbiCoder.encode(
          ['uint8', 'bytes'],
          [toBN(1), expectedFunctionData], // code = 1 means RECEIVE_DELEGATION_CODE
        )
        const expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
          grt.address,
          staking.address,
          mockL2Staking.address,
          actualDelegation,
          expectedCallhookData,
        )

        const tx = staking
          .connect(delegator.signer)
          .migrateDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        // seqNum is 2 because the first bridge call was in migrateStakeToL2
        await expect(tx)
          .emit(l1GraphTokenGateway, 'TxToL2')
          .withArgs(staking.address, mockL2Gateway.address, toBN(2), expectedL2Data)
        await expect(tx)
          .emit(staking, 'DelegationMigratedToL2')
          .withArgs(
            delegator.address,
            l2Delegator.address,
            indexer.address,
            l2Indexer.address,
            actualDelegation,
          )
      })
      it('sets the delegation shares to zero so cannot be called twice', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)
        await staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        await staking
          .connect(delegator.signer)
          .migrateDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        const tx = staking
          .connect(delegator.signer)
          .migrateDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx).revertedWith('delegation == 0')
      })
      it('can be called again if the delegator added more delegation (edge case)', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)
        const actualDelegation = tokensToDelegate.sub(
          tokensToDelegate.mul(delegationTaxPPM).div(1000000),
        )
        await staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        await staking
          .connect(delegator.signer)
          .migrateDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)

        const tx = staking
          .connect(delegator.signer)
          .migrateDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )
        await expect(tx)
          .emit(staking, 'DelegationMigratedToL2')
          .withArgs(
            delegator.address,
            l2Delegator.address,
            indexer.address,
            l2Indexer.address,
            actualDelegation,
          )
      })
      it('rejects calls if the ETH value is larger than expected', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)
        await staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        const tx = staking
          .connect(delegator.signer)
          .migrateDelegationToL2(
            indexer.address,
            l2Delegator.address,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)).add(1),
            },
          )
        await expect(tx).revertedWith('INVALID_ETH_AMOUNT')
      })
    })
    describe('migrateLockedDelegationToL2', function () {
      it('sends delegated tokens to L2 like migrateDelegationToL2, but gets the beneficiary and ETH from the L1GraphTokenLockMigrator', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)
        const actualDelegation = tokensToDelegate.sub(
          tokensToDelegate.mul(delegationTaxPPM).div(1000000),
        )

        await staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        const expectedFunctionData = defaultAbiCoder.encode(
          ['tuple(address,address)'],
          [[l2Indexer.address, l2Delegator.address]],
        )

        const expectedCallhookData = defaultAbiCoder.encode(
          ['uint8', 'bytes'],
          [toBN(1), expectedFunctionData], // code = 1 means RECEIVE_DELEGATION_CODE
        )
        const expectedL2Data = await l1GraphTokenGateway.getOutboundCalldata(
          grt.address,
          staking.address,
          mockL2Staking.address,
          actualDelegation,
          expectedCallhookData,
        )

        await l1GraphTokenLockMigrator.setMigratedAddress(delegator.address, l2Delegator.address)

        const oldMigratorEthBalance = await provider().getBalance(l1GraphTokenLockMigrator.address)
        const tx = staking
          .connect(delegator.signer)
          .migrateLockedDelegationToL2(indexer.address, maxGas, gasPriceBid, maxSubmissionCost)
        // seqNum is 2 because the first bridge call was in migrateStakeToL2
        await expect(tx)
          .emit(l1GraphTokenGateway, 'TxToL2')
          .withArgs(staking.address, mockL2Gateway.address, toBN(2), expectedL2Data)
        await expect(tx)
          .emit(staking, 'DelegationMigratedToL2')
          .withArgs(
            delegator.address,
            l2Delegator.address,
            indexer.address,
            l2Indexer.address,
            actualDelegation,
          )
        expect(await provider().getBalance(l1GraphTokenLockMigrator.address)).to.equal(
          oldMigratorEthBalance.sub(maxSubmissionCost).sub(gasPriceBid.mul(maxGas)),
        )
      })
      it('rejects calls if the migrator contract returns a zero address beneficiary', async function () {
        const tokensToDelegate = toGRT('10000')
        await staking.connect(delegator.signer).delegate(indexer.address, tokensToDelegate)
        const actualDelegation = tokensToDelegate.sub(
          tokensToDelegate.mul(delegationTaxPPM).div(1000000),
        )
        await staking
          .connect(indexer.signer)
          .migrateStakeToL2(
            l2Indexer.address,
            minimumIndexerStake,
            maxGas,
            gasPriceBid,
            maxSubmissionCost,
            {
              value: maxSubmissionCost.add(gasPriceBid.mul(maxGas)),
            },
          )

        const tx = staking
          .connect(delegator.signer)
          .migrateLockedDelegationToL2(indexer.address, maxGas, gasPriceBid, maxSubmissionCost)
        await expect(tx).revertedWith('LOCK NOT MIGRATED')
      })
    })
  })
})
