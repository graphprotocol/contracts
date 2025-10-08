import fs from 'fs'
import hre from 'hardhat'
const { ethers } = hre
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { Contract } from 'ethers'

/**
 * Helper class for working with GraphToken in tests
 * This provides a consistent interface for minting tokens
 * and managing minters
 */
export class GraphTokenHelper {
  private graphToken: Contract
  private governor: SignerWithAddress

  /**
   * Create a new GraphTokenHelper
   * @param graphToken The GraphToken instance
   * @param governor The governor account
   */
  constructor(graphToken: Contract, governor: SignerWithAddress) {
    this.graphToken = graphToken
    this.governor = governor
  }

  /**
   * Get the GraphToken instance
   */
  getToken(): Contract {
    return this.graphToken
  }

  /**
   * Get the GraphToken address
   */
  async getAddress(): Promise<string> {
    return await this.graphToken.getAddress()
  }

  /**
   * Mint tokens to an address
   */
  async mint(to: string, amount: bigint): Promise<void> {
    await (this.graphToken as any).connect(this.governor).mint(to, amount)
  }

  /**
   * Add a minter to the GraphToken
   */
  async addMinter(minter: string): Promise<void> {
    await (this.graphToken as any).connect(this.governor).addMinter(minter)
  }

  /**
   * Deploy a new GraphToken for testing
   * @param {SignerWithAddress} governor The governor account
   * @returns {Promise<GraphTokenHelper>}
   */
  static async deploy(governor) {
    // Load the GraphToken artifact directly from the contracts package
    const graphTokenArtifactPath = require.resolve(
      '@graphprotocol/contracts/artifacts/contracts/token/GraphToken.sol/GraphToken.json',
    )
    const GraphTokenArtifact = JSON.parse(fs.readFileSync(graphTokenArtifactPath, 'utf8'))

    // Create a contract factory using the artifact
    const GraphTokenFactory = new ethers.ContractFactory(GraphTokenArtifact.abi, GraphTokenArtifact.bytecode, governor)

    // Deploy the contract
    const graphToken = await GraphTokenFactory.deploy(ethers.parseEther('1000000000'))
    await graphToken.waitForDeployment()

    return new GraphTokenHelper(graphToken as any, governor)
  }

  /**
   * Create a GraphTokenHelper for an existing GraphToken on a forked network
   * @param {string} tokenAddress The GraphToken address
   * @param {SignerWithAddress} governor The governor account
   * @returns {Promise<GraphTokenHelper>}
   */
  static async forFork(tokenAddress, governor) {
    // Get the GraphToken at the specified address
    const graphToken = await ethers.getContractAt('IGraphToken', tokenAddress)

    // Create a helper
    const helper = new GraphTokenHelper(graphToken as any, governor)

    return helper
  }
}

// GraphTokenHelper is already exported above
