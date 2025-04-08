import type { HorizonStakingExtension, L2GraphToken } from '../../deployments/horizon/index'
import type { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers'

/* //////////////////////////////////////////////////////////////
                            EXPORTS
////////////////////////////////////////////////////////////// */

export const HorizonStakingExtensionActions = {
  collect,
}

/* ////////////////////////////////////////////////////////////
                        STAKING EXTENSION
////////////////////////////////////////////////////////////// */

interface CollectParams {
  horizonStaking: HorizonStakingExtension
  graphToken: L2GraphToken
  gateway: HardhatEthersSigner
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
  graphToken: L2GraphToken,
  signer: HardhatEthersSigner,
  spender: string,
  tokens: bigint,
): Promise<void> {
  const approveTx = await graphToken.connect(signer).approve(spender, tokens)
  await approveTx.wait()
}
