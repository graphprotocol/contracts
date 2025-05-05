import {
  SnapshotRestorer,
  takeSnapshot as hardhatTakeSnapshot,
} from '@nomicfoundation/hardhat-network-helpers'

export async function takeSnapshot(): Promise<SnapshotRestorer> {
  return hardhatTakeSnapshot()
}

export async function restoreSnapshot(snapshot: SnapshotRestorer): Promise<void> {
  return snapshot.restore()
}

export type { SnapshotRestorer } from '@nomicfoundation/hardhat-network-helpers'
