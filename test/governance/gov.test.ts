import { expect } from 'chai'
import { ethers } from '@nomiclabs/buidler'

import { GraphGovernance } from '../../build/typechain/contracts/GraphGovernance'

import { deployGraphGovernance } from '../lib/deployment'
import { getAccounts, Account, randomHexBytes } from '../lib/testHelpers'

const { AddressZero, HashZero } = ethers.constants

enum ProposalStatus {
  Null,
  Unresolved,
  Approved,
  Rejected,
}

describe('GraphGovernance', () => {
  let deployer: Account
  let governor: Account
  let proposer: Account
  let notProposer: Account

  let gov: GraphGovernance

  beforeEach(async function () {
    ;[deployer, governor, proposer, notProposer] = await getAccounts()

    gov = await deployGraphGovernance(deployer.signer, governor.address)
  })

  describe('proposers', function () {
    it('should add a proposer', async function () {
      expect(await gov.isProposer(proposer.address)).eq(false)
      const tx = gov.connect(governor.signer).setProposer(proposer.address, true)
      await expect(tx).emit(gov, 'ProposerUpdated').withArgs(proposer.address, true)
      expect(await gov.isProposer(proposer.address)).eq(true)
    })

    it('reject add empty proposer', async function () {
      const tx = gov.connect(governor.signer).setProposer(AddressZero, true)
      await expect(tx).revertedWith('!account')
    })

    it('reject add if not allowed', async function () {
      const tx = gov.connect(proposer.signer).setProposer(proposer.address, true)
      await expect(tx).revertedWith('Only Governor can call')
    })
  })

  describe('proposals', function () {
    const metadata = randomHexBytes(32)

    beforeEach(async function () {
      await gov.connect(governor.signer).setProposer(proposer.address, true)
    })

    it('should create a proposal', async function () {
      const tx = gov.connect(proposer.signer).createProposal(metadata)
      await expect(tx).emit(gov, 'ProposalCreated').withArgs(proposer.address, metadata)
      expect(await gov.isProposalCreated(metadata)).eq(true)
    })

    it('reject create a proposal if not allowed', async function () {
      const tx = gov.connect(notProposer.signer).createProposal(metadata)
      await expect(tx).revertedWith('!proposer')
    })

    it('reject create a proposal with empty metadata', async function () {
      const tx = gov.connect(proposer.signer).createProposal(HashZero)
      await expect(tx).revertedWith('!metadata')
    })

    it('reject approve a proposal if not created', async function () {
      const tx = gov.connect(governor.signer).approveProposal(metadata)
      await expect(tx).revertedWith('!proposal')
    })

    it('reject reject a proposal if not created', async function () {
      const tx = gov.connect(governor.signer).rejectProposal(metadata)
      await expect(tx).revertedWith('!proposal')
    })

    context('> proposal created', function () {
      beforeEach(async function () {
        await gov.connect(proposer.signer).createProposal(metadata)
      })

      it('should approve a proposal', async function () {
        const tx = gov.connect(governor.signer).approveProposal(metadata)
        await expect(tx).emit(gov, 'ProposalApproved').withArgs(governor.address, metadata)
        expect(await gov.getProposalStatus(metadata)).eq(ProposalStatus.Approved)
      })

      it('should reject a proposal', async function () {
        const tx = gov.connect(governor.signer).rejectProposal(metadata)
        await expect(tx).emit(gov, 'ProposalRejected').withArgs(governor.address, metadata)
        expect(await gov.getProposalStatus(metadata)).eq(ProposalStatus.Rejected)
      })

      it('reject create a proposal if already created', async function () {
        const tx = gov.connect(proposer.signer).createProposal(metadata)
        await expect(tx).revertedWith('exists')
      })

      it('reject approve a proposal if not allowed', async function () {
        const tx = gov.connect(proposer.signer).approveProposal(metadata)
        await expect(tx).revertedWith('Only Governor can call')
      })

      it('reject reject a proposal if not allowed', async function () {
        const tx = gov.connect(proposer.signer).rejectProposal(metadata)
        await expect(tx).revertedWith('Only Governor can call')
      })
    })

    context('> proposal resolved', function () {
      beforeEach(async function () {
        await gov.connect(proposer.signer).createProposal(metadata)
        await gov.connect(governor.signer).approveProposal(metadata)
      })

      it('reject approve a proposal if resolved', async function () {
        const tx = gov.connect(governor.signer).approveProposal(metadata)
        await expect(tx).revertedWith('resolved')
      })

      it('reject reject a proposal if resolved', async function () {
        const tx = gov.connect(governor.signer).rejectProposal(metadata)
        await expect(tx).revertedWith('resolved')
      })
    })
  })
})
