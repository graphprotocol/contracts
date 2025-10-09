import { Contract } from 'ethers'
import hre from 'hardhat'
const { ethers } = hre

/**
 * Deploy a contract for testing and initialize it
 * @param contractName Name of the contract to deploy
 * @param args Constructor arguments
 * @param initializerArgs Arguments for the initializer function
 * @returns Deployed contract instance
 */
export async function deployUpgradeable<T extends Contract>(
  contractName: string,
  args: unknown[] = [],
  initializerArgs: unknown[] = [],
): Promise<T> {
  const factory = await ethers.getContractFactory(contractName)

  // Deploy contract
  const contract = await factory.deploy(...args)
  await contract.waitForDeployment()

  // Call initialize function
  if (initializerArgs.length > 0) {
    const tx = await (contract as any).initialize(...initializerArgs)
    await tx.wait()
  }

  return contract as T
}
