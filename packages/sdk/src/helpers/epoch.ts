import { mine } from './mine'

interface IEpochManager {
  epochLength(): Promise<{ sub: (value: any) => any }>
  currentEpochBlockSinceStart(): Promise<{ sub: (value: any) => any }>
}

export type PartialEpochManager = Pick<IEpochManager, 'epochLength' | 'currentEpochBlockSinceStart'>

export async function mineEpoch(epochManager: PartialEpochManager, epochs?: number): Promise<void> {
  epochs = epochs ?? 1
  for (let i = 0; i < epochs; i++) {
    epochManager
    await _mineEpoch(epochManager)
  }
}

async function _mineEpoch(epochManager: PartialEpochManager): Promise<void> {
  const blocksSinceEpoch = await epochManager.currentEpochBlockSinceStart()
  const epochLen = await epochManager.epochLength()
  return mine(epochLen.sub(blocksSinceEpoch))
}
