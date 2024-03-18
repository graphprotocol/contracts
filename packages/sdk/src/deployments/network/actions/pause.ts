import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { GraphNetworkContracts } from '../deployment/contracts/load'
import { GraphNetworkAction } from './types'

export const setPausedProtocol: GraphNetworkAction<{ paused: boolean }> = async (
  contracts: GraphNetworkContracts,
  governorOrPauseGuardian: SignerWithAddress,
  args: { paused: boolean },
): Promise<void> => {
  const { paused } = args
  const { Controller } = contracts

  console.log(`\nSetting protocol paused to ${paused}...`)
  const tx = await Controller.connect(governorOrPauseGuardian).setPaused(paused)
  await tx.wait()
}

export const setPausedBridge: GraphNetworkAction<{ paused: boolean }> = async (
  contracts: GraphNetworkContracts,
  governorOrPauseGuardian: SignerWithAddress,
  args: { paused: boolean },
): Promise<void> => {
  const { paused } = args
  const { GraphTokenGateway } = contracts

  console.log(`\nSetting bridge ${GraphTokenGateway.address} paused to ${paused}...`)
  const tx = await GraphTokenGateway.connect(governorOrPauseGuardian).setPaused(paused)
  await tx.wait()
}
