import { Contract, ethers as ethersLib } from 'ethers'
import fs from 'fs'
import { createRequire } from 'module'

import { getEthers, type HardhatEthersSigner } from './ethersHelper'

// Create require for ESM compatibility (to resolve package paths)
const require = createRequire(import.meta.url)

/**
 * Helper class for working with GraphToken in tests
 * This provides a consistent interface for minting tokens
 * and managing minters
 */
export class GraphTokenHelper {
  private graphToken: Contract
  private governor: HardhatEthersSigner

  /**
   * Create a new GraphTokenHelper
   * @param graphToken The GraphToken instance
   * @param governor The governor account
   */
  constructor(graphToken: Contract, governor: HardhatEthersSigner) {
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
   * @param {HardhatEthersSigner} governor The governor account
   * @returns {Promise<GraphTokenHelper>}
   */
  static async deploy(governor: HardhatEthersSigner) {
    const ethers = await getEthers()

    // Load the GraphToken artifact directly from the contracts package
    const graphTokenArtifactPath =
      require.resolve('@graphprotocol/contracts/artifacts/contracts/token/GraphToken.sol/GraphToken.json')
    const GraphTokenArtifact = JSON.parse(fs.readFileSync(graphTokenArtifactPath, 'utf8'))

    // Create a contract factory using the artifact
    const GraphTokenFactory = new ethers.ContractFactory(GraphTokenArtifact.abi, GraphTokenArtifact.bytecode, governor)

    // Deploy the contract
    const graphToken = await GraphTokenFactory.deploy(ethersLib.parseEther('1000000000'))
    await graphToken.waitForDeployment()

    return new GraphTokenHelper(graphToken as any, governor)
  }

  /**
   * Create a GraphTokenHelper for an existing GraphToken on a forked network
   * @param {string} tokenAddress The GraphToken address
   * @param {HardhatEthersSigner} governor The governor account
   * @returns {Promise<GraphTokenHelper>}
   */
  static async forFork(tokenAddress: string, governor: HardhatEthersSigner) {
    const ethers = await getEthers()

    // Get the GraphToken at the specified address
    const graphToken = await ethers.getContractAt('IGraphToken', tokenAddress)

    // Create a helper
    const helper = new GraphTokenHelper(graphToken as any, governor)

    return helper
  }
}
