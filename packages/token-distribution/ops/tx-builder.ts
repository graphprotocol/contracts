import fs from 'fs'
import path from 'path'

export interface BuilderTx {
  to: string
  data: string
  value: number | string
  contractMethod?: null
  contractInputsValues?: null
}

interface TxBuilderContents {
  createdAt: number
  chainId: string
  transactions: BuilderTx[]
}

export class TxBuilder {
  contents: TxBuilderContents
  outputFile: string

  constructor(chainId: string, _template?: string) {
    // Template file
    const template = _template ?? 'tx-builder-template.json'
    const templateFilename = path.join(__dirname, template)

    // Output file
    const dateTime = new Date().getTime()
    this.outputFile = path.join(__dirname, `tx-builder-${dateTime}.json`)

    // Load template
    this.contents = JSON.parse(fs.readFileSync(templateFilename, 'utf8'))
    this.contents.createdAt = dateTime
    this.contents.chainId = chainId
  }

  addTx(tx: BuilderTx) {
    this.contents.transactions.push({ ...tx, contractMethod: null, contractInputsValues: null })
  }

  saveToFile() {
    fs.writeFileSync(this.outputFile, JSON.stringify(this.contents, null, 2))
    return this.outputFile
  }
}
