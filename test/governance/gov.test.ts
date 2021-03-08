import { expect } from 'chai'
import hre from 'hardhat'
import '@nomiclabs/hardhat-ethers'

import { GraphGovernance } from '../../build/typechain/contracts/GraphGovernance'

import { deployProxyAdmin, deployGraphGovernance } from '../lib/deployment'
import { getAccounts, Account, randomHexBytes } from '../lib/testHelpers'

const { ethers } = hre
const { HashZero } = ethers.constants

enum ProposalResolution {
  Null,
  Accepted,
  Rejected,
}

describe.only('GraphGovernance', () => {
  let deployer: Account
  let governor: Account
  let someone: Account

  let gov: GraphGovernance

  beforeEach(async function () {
    ;[deployer, governor, someone] = await getAccounts()

    const proxyAdmin = await deployProxyAdmin(deployer.signer)
    gov = await deployGraphGovernance(deployer.signer, governor.address, proxyAdmin)
  })

  describe('proposals', function () {
    const proposalId = randomHexBytes(32)
    const votesProof = randomHexBytes(32)

    it('should create a proposal', async function () {
      const tx = gov
        .connect(governor.signer)
        .createProposal(proposalId, votesProof, ProposalResolution.Accepted)
      await expect(tx)
        .emit(gov, 'ProposalCreated')
        .withArgs(governor.address, proposalId, votesProof, ProposalResolution.Accepted)
      expect(await gov.isProposalCreated(proposalId)).eq(true)
    })

    it('reject create a proposal if not allowed', async function () {
      const tx = gov
        .connect(someone.signer)
        .createProposal(proposalId, votesProof, ProposalResolution.Accepted)
      await expect(tx).revertedWith('Only Governor can call')
    })

    it('reject create a proposal with empty proposalId', async function () {
      const tx = gov
        .connect(governor.signer)
        .createProposal(HashZero, HashZero, ProposalResolution.Null)
      await expect(tx).revertedWith('!proposalId')
    })

    it('reject create a proposal with empty votes proof', async function () {
      const tx = gov
        .connect(governor.signer)
        .createProposal(proposalId, HashZero, ProposalResolution.Null)
      await expect(tx).revertedWith('!votesProof')
    })

    it('reject create a proposal with empty resolution', async function () {
      const tx = gov
        .connect(governor.signer)
        .createProposal(proposalId, votesProof, ProposalResolution.Null)
      await expect(tx).revertedWith('!resolved')
    })

    context('> proposal created', function () {
      beforeEach(async function () {
        await gov
          .connect(governor.signer)
          .createProposal(proposalId, votesProof, ProposalResolution.Accepted)
      })

      it('should update a proposal', async function () {
        const newVotesProof = randomHexBytes(32)
        const newResolution = ProposalResolution.Rejected
        const tx = gov
          .connect(governor.signer)
          .updateProposal(proposalId, newVotesProof, newResolution)
        await expect(tx)
          .emit(gov, 'ProposalUpdated')
          .withArgs(governor.address, proposalId, newVotesProof, newResolution)
      })

      it('reject create a duplicated proposal', async function () {
        const tx = gov
          .connect(governor.signer)
          .createProposal(proposalId, votesProof, ProposalResolution.Accepted)
        await expect(tx).revertedWith('proposed')
      })

      it('reject update a non-existing proposal', async function () {
        const nonProposalId = randomHexBytes(32)
        const tx = gov
          .connect(governor.signer)
          .updateProposal(nonProposalId, votesProof, ProposalResolution.Accepted)
        await expect(tx).revertedWith('!proposed')
      })

      it('reject update with empty proposalId', async function () {
        const tx = gov
          .connect(governor.signer)
          .updateProposal(HashZero, HashZero, ProposalResolution.Null)
        await expect(tx).revertedWith('!proposalId')
      })

      it('reject update a proposal with empty votes proof', async function () {
        const tx = gov
          .connect(governor.signer)
          .updateProposal(proposalId, HashZero, ProposalResolution.Null)
        await expect(tx).revertedWith('!votesProof')
      })

      it('reject update a proposal with empty resolution', async function () {
        const tx = gov
          .connect(governor.signer)
          .updateProposal(proposalId, votesProof, ProposalResolution.Null)
        await expect(tx).revertedWith('!resolved')
      })
    })
  })
})
