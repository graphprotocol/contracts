import { ethers } from 'hardhat'
import { Contract } from 'ethers'

/**
 * Deploy a contract for testing and initialize it
 * @param contractName Name of the contract to deploy
 * @param args Constructor arguments
 * @param initializerArgs Arguments for the initializer function
 * @returns Deployed contract instance
 */
export async function deployUpgradeable<T extends Contract>(
  contractName: string,
  args: any[] = [],
  initializerArgs: any[] = []
): Promise<T> {
  const factory = await ethers.getContractFactory(contractName)

  // Deploy contract
  const contract = await factory.deploy(...args)
  await contract.waitForDeployment()

  // Call initialize function
  if (initializerArgs.length > 0) {
    const tx = await contract.initialize(...initializerArgs)
    await tx.wait()
  }

  return contract as T
}
