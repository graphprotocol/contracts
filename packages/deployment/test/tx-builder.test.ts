import { expect } from 'chai'
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

import { TxBuilder } from '../lib/tx-builder.js'
import { GovernanceTxExecutor } from '../lib/tx-executor.js'

// ESM equivalent of __dirname
const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

describe('TX Builder', function () {
  const tmpDir = path.join(__dirname, '../.tmp-test')
  const chainId = '42161' // Arbitrum One

  before(function () {
    if (!fs.existsSync(tmpDir)) {
      fs.mkdirSync(tmpDir, { recursive: true })
    }
  })

  after(function () {
    // Cleanup test files
    if (fs.existsSync(tmpDir)) {
      const files = fs.readdirSync(tmpDir)
      for (const file of files) {
        fs.unlinkSync(path.join(tmpDir, file))
      }
      fs.rmdirSync(tmpDir)
    }
  })

  describe('TxBuilder', function () {
    it('should create valid Safe TX Builder JSON', function () {
      const builder = new TxBuilder(chainId, { outputDir: tmpDir })

      builder.addTx({
        to: '0x1234567890123456789012345678901234567890',
        data: '0xabcdef',
        value: '0',
      })

      const outputFile = builder.saveToFile()

      expect(fs.existsSync(outputFile)).to.be.true

      const contents = JSON.parse(fs.readFileSync(outputFile, 'utf8'))

      expect(contents).to.have.property('version')
      expect(contents).to.have.property('chainId', chainId)
      expect(contents).to.have.property('createdAt')
      expect(contents).to.have.property('transactions')
      expect(contents.transactions).to.be.an('array').with.lengthOf(1)

      const tx = contents.transactions[0]
      expect(tx).to.have.property('to', '0x1234567890123456789012345678901234567890')
      expect(tx).to.have.property('data', '0xabcdef')
      expect(tx).to.have.property('value', '0')
      expect(tx).to.have.property('contractMethod', null)
      expect(tx).to.have.property('contractInputsValues', null)
    })

    it('should handle multiple transactions', function () {
      const builder = new TxBuilder(chainId, { outputDir: tmpDir })

      builder.addTx({
        to: '0x1111111111111111111111111111111111111111',
        data: '0x11',
        value: '0',
      })

      builder.addTx({
        to: '0x2222222222222222222222222222222222222222',
        data: '0x22',
        value: '100',
      })

      builder.addTx({
        to: '0x3333333333333333333333333333333333333333',
        data: '0x33',
        value: '0',
      })

      const outputFile = builder.saveToFile()
      const contents = JSON.parse(fs.readFileSync(outputFile, 'utf8'))

      expect(contents.transactions).to.have.lengthOf(3)
      expect(contents.transactions[0].to).to.equal('0x1111111111111111111111111111111111111111')
      expect(contents.transactions[1].to).to.equal('0x2222222222222222222222222222222222222222')
      expect(contents.transactions[2].to).to.equal('0x3333333333333333333333333333333333333333')
    })

    it('should use custom template if provided', function () {
      const templatePath = path.join(tmpDir, 'custom-template.json')
      const customTemplate = {
        version: '1.0',
        chainId: '1',
        createdAt: 0,
        meta: { name: 'Custom Template' },
        transactions: [],
      }

      fs.writeFileSync(templatePath, JSON.stringify(customTemplate))

      const builder = new TxBuilder(chainId, {
        template: templatePath,
        outputDir: tmpDir,
      })

      builder.addTx({
        to: '0x4444444444444444444444444444444444444444',
        data: '0x44',
        value: '0',
      })

      const outputFile = builder.saveToFile()
      const contents = JSON.parse(fs.readFileSync(outputFile, 'utf8'))

      expect(contents.meta).to.deep.equal({ name: 'Custom Template' })
      expect(contents.chainId).to.equal(chainId) // Should be overridden
    })
  })

  describe('GovernanceTxExecutor', function () {
    // parseBatch doesn't actually use hre, so we pass a mock
    const mockHre = {}

    it('should parse Safe TX Builder JSON', function () {
      const builder = new TxBuilder(chainId, { outputDir: tmpDir })

      builder.addTx({
        to: '0x5555555555555555555555555555555555555555',
        data: '0x55',
        value: '0',
      })

      const outputFile = builder.saveToFile()

      const executor = new GovernanceTxExecutor(mockHre)
      const batch = executor.parseBatch(outputFile)

      expect(batch).to.have.property('chainId', chainId)
      expect(batch.transactions).to.have.lengthOf(1)
      expect(batch.transactions[0].to).to.equal('0x5555555555555555555555555555555555555555')
    })

    it('should validate TX batch structure', function () {
      const builder = new TxBuilder(chainId, { outputDir: tmpDir })

      // Add transactions with all required fields
      builder.addTx({
        to: '0x6666666666666666666666666666666666666666',
        data: '0x66',
        value: '0',
      })

      const outputFile = builder.saveToFile()
      const executor = new GovernanceTxExecutor(mockHre)
      const batch = executor.parseBatch(outputFile)

      // Validate structure
      for (const tx of batch.transactions) {
        expect(tx).to.have.property('to').that.is.a('string')
        expect(tx).to.have.property('data').that.is.a('string')
        expect(tx).to.have.property('value')
        expect(tx.to).to.match(/^0x[a-fA-F0-9]{40}$/) // Valid Ethereum address
        expect(tx.data).to.match(/^0x[a-fA-F0-9]*$/) // Valid hex string
      }
    })
  })
})
