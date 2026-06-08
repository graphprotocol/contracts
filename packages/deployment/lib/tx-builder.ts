import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

// ESM equivalent of __dirname
const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

/**
 * Core transaction fields (Safe TX Builder compatible)
 */
export interface BuilderTx {
  to: string
  data: string
  value: string | number
  // The Safe Tx Builder UI expects these keys even when null
  contractMethod?: null
  contractInputsValues?: null
}

/**
 * Human-readable decoded function call
 */
export interface DecodedCall {
  /** Function signature, e.g., "upgradeAndCall(address,address,bytes)" */
  function: string
  /** Decoded arguments with labels */
  args: Record<string, string>
}

/**
 * State change information for upgrade transactions
 */
export interface StateChange {
  /** Current value (before TX) */
  current: string
  /** New value (after TX) */
  new: string
}

/**
 * Rich transaction metadata for governance transparency
 */
export interface TxMetadata {
  /** Human-readable label for 'to' address, e.g., "IssuanceAllocator_ProxyAdmin" */
  toLabel?: string
  /** Decoded function call */
  decoded?: DecodedCall
  /** State changes this TX will cause */
  stateChanges?: Record<string, StateChange>
  /** Related contract name */
  contractName?: string
  /** Notes for governance reviewers */
  notes?: string
}

/**
 * Enhanced transaction with metadata (internal representation)
 */
export interface EnhancedBuilderTx extends BuilderTx {
  /** Rich metadata for governance review (not part of Safe TX format) */
  _metadata?: TxMetadata
}

/**
 * Safe TX Builder JSON format (compatible with Safe{Wallet} Transaction Builder)
 */
interface SafeTxBuilderContents {
  version: string
  chainId: string
  createdAt: number
  meta?: {
    name?: string
    description?: string
    txBuilderVersion?: string
    createdFromSafeAddress?: string
    createdFromOwnerAddress?: string
    checksum?: string
    [key: string]: unknown
  }
  transactions: BuilderTx[]
}

/**
 * Enhanced TX builder contents with governance metadata
 */
interface EnhancedTxBuilderContents extends SafeTxBuilderContents {
  /** Rich metadata for each transaction (parallel array to transactions) */
  _transactionMetadata?: TxMetadata[]
}

export interface TxBuilderOptions {
  template?: string
  outputDir?: string
  /** Optional name for the output file (without extension). If not provided, uses timestamp. */
  name?: string
  /** Optional metadata to describe the transaction batch */
  meta?: {
    name?: string
    description?: string
  }
}

export class TxBuilder {
  private contents: EnhancedTxBuilderContents
  private metadata: TxMetadata[] = []
  public readonly outputFile: string

  constructor(chainId: string | number | bigint, options: TxBuilderOptions = {}) {
    const templatePath = options.template ?? path.resolve(__dirname, 'tx-builder-template.json')
    const createdAt = Date.now()

    this.contents = JSON.parse(fs.readFileSync(templatePath, 'utf8')) as EnhancedTxBuilderContents
    this.contents.createdAt = createdAt
    this.contents.chainId = chainId.toString()
    if (!Array.isArray(this.contents.transactions)) {
      this.contents.transactions = []
    }

    // Override metadata if provided
    if (options.meta) {
      this.contents.meta = {
        ...this.contents.meta,
        ...options.meta,
      }
    }

    const outputDir = options.outputDir ?? process.cwd()
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true })
    }

    const filename = options.name ? `${options.name}.json` : `tx-builder-${createdAt}.json`
    this.outputFile = path.join(outputDir, filename)
  }

  /**
   * Add a transaction to the batch
   * @param tx - Transaction data
   * @param metadata - Optional rich metadata for governance review
   */
  addTx(tx: BuilderTx, metadata?: TxMetadata) {
    this.contents.transactions.push({ ...tx, contractMethod: null, contractInputsValues: null })
    this.metadata.push(metadata ?? {})
  }

  /**
   * Get the transactions in the batch
   */
  getTransactions(): readonly BuilderTx[] {
    return this.contents.transactions
  }

  /**
   * Get the metadata for transactions
   */
  getMetadata(): readonly TxMetadata[] {
    return this.metadata
  }

  /**
   * Check if the batch has any transactions
   */
  isEmpty(): boolean {
    return this.contents.transactions.length === 0
  }

  /**
   * Save to file with metadata for governance review
   * Outputs both Safe-compatible format and enhanced metadata
   */
  saveToFile() {
    // Include metadata in output for governance review
    const output: EnhancedTxBuilderContents = {
      ...this.contents,
      _transactionMetadata: this.metadata.length > 0 ? this.metadata : undefined,
    }
    fs.writeFileSync(this.outputFile, JSON.stringify(output, null, 2) + '\n')
    return this.outputFile
  }
}
