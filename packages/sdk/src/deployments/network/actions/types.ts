import type { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import type { GraphNetworkContracts } from '../deployment/contracts/load'

export type GraphNetworkAction<A, R = void> = (
  contracts: GraphNetworkContracts,
  signer: SignerWithAddress,
  args: A,
) => Promise<R>
