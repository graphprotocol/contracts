import { expect } from 'chai'
import { ethers, ContractTransaction, BigNumber, Event } from 'ethers'
import { solidityKeccak256 } from 'ethers/lib/utils'
import { SubgraphDeploymentID } from '@graphprotocol/common-ts'

import { LegacyGNSMock } from '../build/types/LegacyGNSMock'
import { GraphToken } from '../build/types/GraphToken'
import { Curation } from '../build/types/Curation'
import { SubgraphNFT } from '../build/types/SubgraphNFT'

import { getAccounts, randomHexBytes, Account, toGRT, getChainID } from './lib/testHelpers'
import { NetworkFixture } from './lib/fixtures'
import { toBN, formatGRT } from './lib/testHelpers'
import { getContractAt } from '../cli/network'
import { deployContract } from './lib/deployment'
import { BancorFormula } from '../build/types/BancorFormula'
import { network } from '../cli'
import { Controller } from '../build/types/Controller'
import { GraphProxyAdmin } from '../build/types/GraphProxyAdmin'
import { L2GNS } from '../build/types/L1GNS'

const { AddressZero, HashZero } = ethers.constants

describe('L2GNS', () => {
  describe('receiving a subgraph from L1', function () {
    it('cannot be called by someone other than the L2GraphTokenGateway')
    it('creates a subgraph in a disabled state')
    it('does not conflict with a locally created subgraph')
  })

  describe('finishing a subgraph migration from L1', function () {
    it('publishes the migrated subgraph and mints signal with no tax')
    it('cannot be called by someone other than the subgraph owner')
    it('rejects calls for a subgraph that was not migrated')
    it('rejects calls to a pre-curated subgraph deployment')
    it('rejects calls if the subgraph deployment ID is zero')
  })

  describe('claiming a curator balance using a proof', function () {
    it('verifies a proof and assigns a curator balance')
    it('adds the balance to any existing balance for the curator')
    it('rejects calls with an invalid proof')
    it('rejects calls for a subgraph that was not migrated')
    it('rejects calls if the balance was already claimed')
    it('rejects calls with proof from a different curator')
    it('rejects calls with proof from a different contract')
    it('rejects calls with a proof from a different block')
  })
  describe('claiming a curator balance with a message from L1', function () {
    it('assigns a curator balance to a beneficiary')
    it('adds the balance to any existing balance for the beneficiary')
    it('can only be called from the gateway')
    it('rejects calls for a subgraph that was not migrated')
    it('rejects calls if the balance was already claimed')
  })
})
