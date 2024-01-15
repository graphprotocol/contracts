import { Contract, ContractTransaction, ethers } from 'ethers'

import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import type { GraphNetworkContracts } from '../deployment/contracts/load'
import type { GraphNetworkContractName } from '../deployment/contracts/list'
import type { GraphNetworkAction } from './types'

type GovernedContract = Contract & {
  pendingGovernor?: (overrides: ethers.CallOverrides) => Promise<string>
  acceptOwnership?: (overrides: ethers.CallOverrides) => Promise<string>
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

  const pendingGovernor = await (contract as GovernedContract).connect(signer).pendingGovernor()

  if (pendingGovernor === ethers.constants.AddressZero) {
    console.log(`No pending governor for ${contract.address}`)
    return
  }

  if (pendingGovernor === signer.address) {
    console.log(`Accepting ownership of ${contract.address}`)
    const tx = await (contract as GovernedContract).connect(signer).acceptOwnership()
    await tx.wait()
    return tx
  } else {
    console.log(
      `Signer ${signer.address} is not the pending governor of ${contract.address}, it is ${pendingGovernor}`,
    )
  }
}
