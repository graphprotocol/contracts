import hre from 'hardhat'
import { expect } from 'chai'
import '@nomiclabs/hardhat-ethers'

import { GraphGovernance } from '../../build/types/GraphGovernance'

import { deployProxyAdmin, deployGraphGovernance } from '../lib/deployment'
import { randomHexBytes } from '@graphprotocol/sdk'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

const { ethers } = hre
const { HashZero } = ethers.constants

enum ProposalResolution {
  Null,
  Accepted,
  Rejected,
}

describe('GraphGovernance', () => {
  const graph = hre.graph()
  let deployer: SignerWithAddress
  let governor: SignerWithAddress
  let someone: SignerWithAddress

  let gov: GraphGovernance

  beforeEach(async function () {
    ;[deployer, governor, someone] = await graph.getTestAccounts()

    const proxyAdmin = await deployProxyAdmin(deployer)
    gov = await deployGraphGovernance(deployer, governor.address, proxyAdmin)
  })

  describe('proposals', function () {
    const proposalId = randomHexBytes(32)
    const votes = randomHexBytes(32)
    const metadata = randomHexBytes(32)

    it('should create a proposal', async function () {
      const tx = gov
        .connect(governor)
        .createProposal(proposalId, votes, metadata, ProposalResolution.Accepted)
      await expect(tx)
        .emit(gov, 'ProposalCreated')
        .withArgs(proposalId, votes, metadata, ProposalResolution.Accepted)
      expect(await gov.isProposalCreated(proposalId)).eq(true)

      const storedProposal = await gov.proposals(proposalId)
      expect(storedProposal.metadata).eq(metadata)
      expect(storedProposal.votes).eq(votes)
      expect(storedProposal.resolution).eq(ProposalResolution.Accepted)
    })

    it('reject create a proposal if not allowed', async function () {
      const tx = gov
        .connect(someone)
        .createProposal(proposalId, votes, metadata, ProposalResolution.Accepted)
      await expect(tx).revertedWith('Only Governor can call')
    })

    it('reject create a proposal with empty proposalId', async function () {
      const tx = gov
        .connect(governor)
        .createProposal(HashZero, HashZero, metadata, ProposalResolution.Null)
      await expect(tx).revertedWith('!proposalId')
    })

    it('reject create a proposal with empty votes proof', async function () {
      const tx = gov
        .connect(governor)
        .createProposal(proposalId, HashZero, metadata, ProposalResolution.Null)
      await expect(tx).revertedWith('!votes')
    })

    it('reject create a proposal with empty resolution', async function () {
      const tx = gov
        .connect(governor)
        .createProposal(proposalId, votes, metadata, ProposalResolution.Null)
      await expect(tx).revertedWith('!resolved')
    })

    context('> proposal created', function () {
      beforeEach(async function () {
        await gov
          .connect(governor)
          .createProposal(proposalId, votes, metadata, ProposalResolution.Accepted)
      })

      it('should update a proposal', async function () {
        const newvotes = randomHexBytes(32)
        const newResolution = ProposalResolution.Rejected
        const tx = gov
          .connect(governor)
          .updateProposal(proposalId, newvotes, metadata, newResolution)
        await expect(tx)
          .emit(gov, 'ProposalUpdated')
          .withArgs(proposalId, newvotes, metadata, newResolution)

        const storedProposal = await gov.proposals(proposalId)
        expect(storedProposal.metadata).eq(metadata)
        expect(storedProposal.votes).eq(newvotes)
        expect(storedProposal.resolution).eq(newResolution)
      })

      it('reject create a duplicated proposal', async function () {
        const tx = gov
          .connect(governor)
          .createProposal(proposalId, votes, metadata, ProposalResolution.Accepted)
        await expect(tx).revertedWith('proposed')
      })

      it('reject update a non-existing proposal', async function () {
        const nonProposalId = randomHexBytes(32)
        const tx = gov
          .connect(governor)
          .updateProposal(nonProposalId, votes, metadata, ProposalResolution.Accepted)
        await expect(tx).revertedWith('!proposed')
      })

      it('reject update with empty proposalId', async function () {
        const tx = gov
          .connect(governor)
          .updateProposal(HashZero, HashZero, metadata, ProposalResolution.Null)
        await expect(tx).revertedWith('!proposalId')
      })

      it('reject update a proposal with empty votes proof', async function () {
        const tx = gov
          .connect(governor)
          .updateProposal(proposalId, HashZero, metadata, ProposalResolution.Null)
        await expect(tx).revertedWith('!votes')
      })

      it('reject update a proposal with empty resolution', async function () {
        const tx = gov
          .connect(governor)
          .updateProposal(proposalId, votes, metadata, ProposalResolution.Null)
        await expect(tx).revertedWith('!resolved')
      })
    })
  })
})
