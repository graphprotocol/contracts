import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { Contract, ContractTransaction, ethers } from 'ethers'

import type { GraphNetworkContractName } from '../deployment/contracts/list'
import type { GraphNetworkContracts } from '../deployment/contracts/load'
import type { GraphNetworkAction } from './types'

type GovernedContract = Contract & {
  pendingGovernor?: (_overrides: ethers.CallOverrides) => Promise<string>
  acceptOwnership?: (_overrides: ethers.CallOverrides) => Promise<string>
}

export const acceptOwnership: GraphNetworkAction<
  {
    contractName: GraphNetworkContractName
  },
  ContractTransaction | undefined
> = async (
  contracts: GraphNetworkContracts,
  signer: SignerWithAddress,
  args: { contractName: GraphNetworkContractName },
): Promise<ContractTransaction | undefined> => {
  const { contractName } = args
  const contract = contracts[contractName]

  if (!contract) {
    throw new Error(`Contract ${contractName} not found`)
  }

  let pendingGovernor: string
  try {
    pendingGovernor = await (contract as GovernedContract).connect(signer).pendingGovernor()
  } catch (error) {
    console.log(`Contract ${contract.address} does not have pendingGovernor() method or call failed: ${error}`)
    return
  }

  if (pendingGovernor === ethers.constants.AddressZero) {
    console.log(`No pending governor for ${contract.address}`)
    return
  }

  if (pendingGovernor === signer.address) {
    console.log(`Accepting ownership of ${contract.address}`)
    try {
      const tx = await (contract as GovernedContract).connect(signer).acceptOwnership()
      await tx.wait()
      return tx
    } catch (error) {
      console.log(`Failed to accept ownership of ${contract.address}: ${error}`)
      return
    }
  } else {
    console.log(`Signer ${signer.address} is not the pending governor of ${contract.address}, it is ${pendingGovernor}`)
  }
}
