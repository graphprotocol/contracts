import fs from 'fs'
import path from 'path'

export class TxBuilder {
  contents: any
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

  addTx(tx: any) {
    this.contents.transactions.push({ ...tx, contractMethod: null, contractInputsValues: null })
  }

  saveToFile() {
    fs.writeFileSync(this.outputFile, JSON.stringify(this.contents, null, 2))
    return this.outputFile
  }
}
