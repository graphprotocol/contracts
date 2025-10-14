import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { Contract } from 'ethers'
import hre from 'hardhat'
const { ethers } = hre

/**
 * Helper class for working with GraphToken in tests
 * This provides a consistent interface for minting tokens
 */
export class TokenHelper {
  private token: Contract
  private governor: SignerWithAddress

  /**
   * Create a new TokenHelper
   * @param token The token contract instance
   * @param governor The governor account
   */
  constructor(token: Contract, governor: SignerWithAddress) {
    this.token = token
    this.governor = governor
  }

  /**
   * Get the token contract instance
   * @returns The token contract instance
   */
  public getToken(): Contract {
    return this.token
  }

  /**
   * Get the token address
   * @returns The token address
   */
  public async getAddress(): Promise<string> {
    return await this.token.getAddress()
  }

  /**
   * Mint tokens to an address
   * @param to Address to mint tokens to
   * @param amount Amount of tokens to mint
   */
  public async mint(to: string, amount: bigint): Promise<void> {
    await (this.token as any).connect(this.governor).mint(to, amount)
  }

  /**
   * Add a minter to the token
   * @param minter Address to add as a minter
   */
  public async addMinter(minter: string): Promise<void> {
    await (this.token as any).connect(this.governor).addMinter(minter)
  }

  /**
   * Deploy a new token for testing
   * @param governor The governor account
   * @returns A new TokenHelper instance
   */
  public static async deploy(governor: SignerWithAddress): Promise<TokenHelper> {
    // Deploy a token that implements IGraphToken
    const tokenFactory = await ethers.getContractFactory('TestGraphToken')
    const token = await tokenFactory.deploy()

    // Initialize the token with the governor
    await (token as any).initialize(governor.address)

    return new TokenHelper(token as any, governor)
  }
}
