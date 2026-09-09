import fs from 'fs'
import path from 'path'

import type { BuilderTx, TxBuilder, TxMetadata } from './tx-builder.js'

/**
 * On-disk shape of a saved governance TX bundle. Mirrors `EnhancedTxBuilderContents`
 * from `tx-builder.ts`; declared here as a structural read-only view so the gather
 * code doesn't depend on internal builder types.
 */
interface SavedBundle {
  transactions?: BuilderTx[]
  _transactionMetadata?: TxMetadata[]
}

export interface GatherResult {
  /** Number of TXs appended to the builder (summed across all source bundles). */
  txCount: number
  /** Absolute paths of source bundle files that contributed TXs. Use with {@link markIncorporated}. */
  sourceFiles: string[]
  /** Basenames of the same files, suitable for {@link TxBuilder.markGatheredFrom}. */
  sourceNames: string[]
}

/**
 * Append every per-component bundle matching `{prefix}-{entryName}.json` under
 * `txDir` into the supplied builder, preserving each TX's metadata.
 *
 * Caller supplies the iteration of expected entry names (typically the names
 * yielded by `allUpgradeableEntries()` from `contract-registry.ts`). Bundles
 * that don't exist on disk are silently skipped — absence means "no TX queued
 * for this component" under the file-system-as-current-state invariant.
 *
 * Returns the per-bundle source file paths and basenames so the caller can
 * record provenance on the consolidated bundle (`markGatheredFrom`) and then
 * relocate the sources (`markIncorporated`) after successfully saving.
 */
export function gatherBundles(
  txDir: string,
  builder: TxBuilder,
  entryNames: Iterable<string>,
  prefix: string,
): GatherResult {
  const sourceFiles: string[] = []
  const sourceNames: string[] = []
  let txCount = 0

  for (const name of entryNames) {
    const filename = `${prefix}-${name}.json`
    const fullPath = path.join(txDir, filename)
    if (!fs.existsSync(fullPath)) continue

    const parsed = JSON.parse(fs.readFileSync(fullPath, 'utf8')) as SavedBundle
    const txs = parsed.transactions ?? []
    const metadata = parsed._transactionMetadata ?? []
    for (let i = 0; i < txs.length; i++) {
      builder.addTx(txs[i], metadata[i])
      txCount++
    }
    if (txs.length > 0) {
      sourceFiles.push(fullPath)
      sourceNames.push(filename)
    }
  }

  return { txCount, sourceFiles, sourceNames }
}

/**
 * Move source bundle files into `{txDir}/incorporated/{batchName}/` after they've
 * been consolidated into `{batchName}.json`.
 *
 * Files in the `incorporated/` subdirectory are invisible to
 * `executeGovernanceTxs` (which scans top-level `.json` only), so the
 * consolidated bundle is the unique replayable artifact while the sources
 * remain available for audit until the next consolidation run.
 *
 * `createGovernanceTxBuilder` clears `incorporated/{batchName}/` when a new
 * builder of the same name is constructed, so each run starts from a clean
 * slate and the directory always reflects the current consolidated bundle's
 * sources.
 */
export function markIncorporated(txDir: string, sourceFiles: string[], batchName: string): void {
  if (sourceFiles.length === 0) return
  const dest = path.join(txDir, 'incorporated', batchName)
  fs.mkdirSync(dest, { recursive: true })
  for (const src of sourceFiles) {
    const target = path.join(dest, path.basename(src))
    fs.renameSync(src, target)
  }
}
