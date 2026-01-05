import fs from 'fs'
import path from 'path'

export interface BuilderTx {
  to: string
  data: string
  value: string | number
  // The Safe Tx Builder UI expects these keys even when null
  contractMethod?: null
  contractInputsValues?: null
}

interface TxBuilderContents {
  version: string
  chainId: string
  createdAt: number
  meta?: unknown
  transactions: BuilderTx[]
}

export interface TxBuilderOptions {
  template?: string
  outputDir?: string
}

export class TxBuilder {
  private contents: TxBuilderContents
  public readonly outputFile: string

  constructor(chainId: string | number | bigint, options: TxBuilderOptions = {}) {
    const templatePath = options.template ?? path.resolve(__dirname, 'tx-builder-template.json')
    const createdAt = Date.now()

    this.contents = JSON.parse(fs.readFileSync(templatePath, 'utf8')) as TxBuilderContents
    this.contents.createdAt = createdAt
    this.contents.chainId = chainId.toString()
    if (!Array.isArray(this.contents.transactions)) {
      this.contents.transactions = []
    }

    const outputDir = options.outputDir ?? process.cwd()
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true })
    }

    this.outputFile = path.join(outputDir, `tx-builder-${createdAt}.json`)
  }

  addTx(tx: BuilderTx) {
    this.contents.transactions.push({ ...tx, contractMethod: null, contractInputsValues: null })
  }

  saveToFile() {
    fs.writeFileSync(this.outputFile, JSON.stringify(this.contents, null, 2))
    return this.outputFile
  }
}
