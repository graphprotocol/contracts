/* eslint-disable @typescript-eslint/no-explicit-any */
import { expect } from 'chai'
import { ethers } from 'hardhat'

import { shouldSupportERC165Interface } from '../../utils/testPatterns'
import { deployServiceQualityOracle, deployTestGraphToken, getTestAccounts } from '../helpers/fixtures'
// Import generated interface IDs
import interfaceIds from '../helpers/interfaceIds'

/**
 * Consolidated ERC-165 Interface Compliance Tests
 * Tests interface support across all contracts to reduce duplication
 */
describe('ERC-165 Interface Compliance', () => {
  let accounts: any
  let contracts: any

  before(async () => {
    accounts = await getTestAccounts()

    // Deploy all contracts for interface testing
    const graphToken = await deployTestGraphToken()
    const graphTokenAddress = await graphToken.getAddress()

    const serviceQualityOracle = await deployServiceQualityOracle(graphTokenAddress, accounts.governor)

    contracts = {
      serviceQualityOracle,
    }
  })

  describe(
    'ServiceQualityOracle Interface Compliance',
    shouldSupportERC165Interface(
      () => contracts.serviceQualityOracle,
      interfaceIds.IServiceQualityOracle,
      'IServiceQualityOracle',
    ),
  )

  describe('Interface ID Consistency', () => {
    it('should have consistent interface IDs with Solidity calculations', async () => {
      const InterfaceIdExtractorFactory = await ethers.getContractFactory('InterfaceIdExtractor')
      const extractor = await InterfaceIdExtractorFactory.deploy()

      expect(await extractor.getIServiceQualityOracleId()).to.equal(interfaceIds.IServiceQualityOracle)
    })

    it('should have valid interface IDs (not zero)', () => {
      expect(interfaceIds.IServiceQualityOracle).to.not.equal('0x00000000')
    })
  })
})
