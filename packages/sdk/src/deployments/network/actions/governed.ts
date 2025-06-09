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

  // Safely call pendingGovernor with proper error handling for coverage environment
  const contractWithSigner = (contract as GovernedContract).connect(signer)

  let pendingGovernor: string
  try {
    pendingGovernor = await contractWithSigner.pendingGovernor()
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error)
    console.log(`Contract ${contractName} at ${contract.address} failed to call pendingGovernor(): ${errorMessage}`)
    console.log(`Skipping ownership acceptance for this contract`)
    return
  }

  if (pendingGovernor === ethers.constants.AddressZero) {
    console.log(`No pending governor for ${contract.address}`)
    return
  }

  if (pendingGovernor === signer.address) {
    console.log(`Accepting ownership of ${contract.address}`)

    try {
      const tx = await contractWithSigner.acceptOwnership()
      await tx.wait()
      return tx
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error)
      console.log(`Contract ${contractName} at ${contract.address} failed to call acceptOwnership(): ${errorMessage}`)
      console.log(`Skipping ownership acceptance for this contract`)
      return
    }
  } else {
    console.log(`Signer ${signer.address} is not the pending governor of ${contract.address}, it is ${pendingGovernor}`)
  }
}
