import { IHorizonStaking, IGraphToken } from '../../../typechain-types'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'

/* ////////////////////////////////////////////////////////////
                        STAKING EXTENSION
////////////////////////////////////////////////////////////// */

interface CollectParams {
  horizonStaking: IHorizonStaking
  graphToken: IGraphToken
  gateway: SignerWithAddress
  allocationID: string
  tokens: bigint
}

export async function collect({
  horizonStaking,
  graphToken,
  gateway,
  allocationID,
  tokens,
}: CollectParams): Promise<void> {
  // Approve horizon staking contract to pull tokens from gateway
  await approve(graphToken, gateway, await horizonStaking.getAddress(), tokens)
  
  // Collect query fees
  const collectTx = await horizonStaking.connect(gateway).collect(tokens, allocationID)
  await collectTx.wait()
}

/* ////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
////////////////////////////////////////////////////////////// */

async function approve(
  graphToken: IGraphToken,
  signer: SignerWithAddress,
  spender: string,
  tokens: bigint,
): Promise<void> {
  const approveTx = await graphToken.connect(signer).approve(spender, tokens)
  await approveTx.wait()
}
