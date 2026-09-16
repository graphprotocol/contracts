import { expect } from 'chai'
import fs from 'fs'
import os from 'os'
import path from 'path'

import { claimBundleSlot } from '../lib/execute-governance.js'
import { gatherBundles, markIncorporated } from '../lib/gather-bundles.js'
import { TxBuilder } from '../lib/tx-builder.js'

function writeBundle(dir: string, filename: string, txs: Array<{ to: string; value: string; data: string }>) {
  const file = path.join(dir, filename)
  const payload = {
    version: '1.0',
    chainId: '31337',
    createdAt: Date.now(),
    meta: { name: 'test', description: '' },
    transactions: txs.map((t) => ({ ...t, contractMethod: null, contractInputsValues: null })),
    _transactionMetadata: txs.map((_, i) => ({ contractName: `Source${i}` })),
  }
  fs.writeFileSync(file, JSON.stringify(payload, null, 2) + '\n')
  return file
}

describe('gather-bundles', function () {
  let tmpDir: string

  beforeEach(function () {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'gather-bundles-'))
  })

  afterEach(function () {
    fs.rmSync(tmpDir, { recursive: true, force: true })
  })

  describe('gatherBundles', function () {
    it('appends transactions from matching per-component bundles in iteration order', function () {
      writeBundle(tmpDir, 'upgrade-A.json', [{ to: '0xa', value: '0', data: '0xaa' }])
      writeBundle(tmpDir, 'upgrade-B.json', [
        { to: '0xb1', value: '0', data: '0xbb1' },
        { to: '0xb2', value: '0', data: '0xbb2' },
      ])

      const builder = new TxBuilder('31337', { outputDir: tmpDir, name: 'consolidated' })
      const result = gatherBundles(tmpDir, builder, ['A', 'B'], 'upgrade')

      expect(result.txCount).to.equal(3)
      expect(result.sourceFiles).to.have.lengthOf(2)
      expect(result.sourceFiles[0].endsWith('upgrade-A.json')).to.be.true
      expect(result.sourceFiles[1].endsWith('upgrade-B.json')).to.be.true
      expect(result.sourceNames).to.deep.equal(['upgrade-A.json', 'upgrade-B.json'])

      const txs = builder.getTransactions()
      expect(txs.map((t) => t.to)).to.deep.equal(['0xa', '0xb1', '0xb2'])
    })

    it('preserves per-transaction metadata across the round trip', function () {
      writeBundle(tmpDir, 'upgrade-X.json', [{ to: '0xa', value: '0', data: '0xaa' }])

      const builder = new TxBuilder('31337', { outputDir: tmpDir, name: 'consolidated' })
      gatherBundles(tmpDir, builder, ['X'], 'upgrade')

      const md = builder.getMetadata()
      expect(md).to.have.lengthOf(1)
      expect(md[0].contractName).to.equal('Source0')
    })

    it('silently skips missing per-component bundles', function () {
      writeBundle(tmpDir, 'upgrade-A.json', [{ to: '0xa', value: '0', data: '0xaa' }])

      const builder = new TxBuilder('31337', { outputDir: tmpDir, name: 'consolidated' })
      const result = gatherBundles(tmpDir, builder, ['A', 'Missing', 'Also-Missing'], 'upgrade')

      expect(result.txCount).to.equal(1)
      expect(result.sourceFiles).to.have.lengthOf(1)
      expect(result.sourceNames).to.deep.equal(['upgrade-A.json'])
    })

    it('returns zero counts and empty list when nothing matches', function () {
      const builder = new TxBuilder('31337', { outputDir: tmpDir, name: 'consolidated' })
      const result = gatherBundles(tmpDir, builder, ['A', 'B'], 'upgrade')

      expect(result.txCount).to.equal(0)
      expect(result.sourceFiles).to.deep.equal([])
      expect(result.sourceNames).to.deep.equal([])
      expect(builder.isEmpty()).to.be.true
    })
  })

  describe('markIncorporated', function () {
    it('moves source files into incorporated/<batch>/ preserving basenames', function () {
      const a = writeBundle(tmpDir, 'upgrade-A.json', [{ to: '0xa', value: '0', data: '0xaa' }])
      const b = writeBundle(tmpDir, 'upgrade-B.json', [{ to: '0xb', value: '0', data: '0xbb' }])

      markIncorporated(tmpDir, [a, b], 'my-batch')

      expect(fs.existsSync(a)).to.be.false
      expect(fs.existsSync(b)).to.be.false
      expect(fs.existsSync(path.join(tmpDir, 'incorporated', 'my-batch', 'upgrade-A.json'))).to.be.true
      expect(fs.existsSync(path.join(tmpDir, 'incorporated', 'my-batch', 'upgrade-B.json'))).to.be.true
    })

    it('is a no-op when given an empty source list', function () {
      markIncorporated(tmpDir, [], 'my-batch')
      expect(fs.existsSync(path.join(tmpDir, 'incorporated', 'my-batch'))).to.be.false
    })
  })

  describe('claimBundleSlot', function () {
    it('removes a prior pending bundle at the named slot', function () {
      const file = path.join(tmpDir, 'consolidated.json')
      fs.writeFileSync(file, '{}')

      claimBundleSlot(tmpDir, 'consolidated')

      expect(fs.existsSync(file)).to.be.false
    })

    it('recursively removes a prior incorporated/<name>/ directory', function () {
      const incorporated = path.join(tmpDir, 'incorporated', 'consolidated')
      fs.mkdirSync(incorporated, { recursive: true })
      fs.writeFileSync(path.join(incorporated, 'upgrade-A.json'), '{}')
      fs.writeFileSync(path.join(incorporated, 'upgrade-B.json'), '{}')

      claimBundleSlot(tmpDir, 'consolidated')

      expect(fs.existsSync(incorporated)).to.be.false
    })

    it('is safe to call when neither slot exists', function () {
      expect(() => claimBundleSlot(tmpDir, 'never-existed')).to.not.throw()
    })

    it('only touches the named slot, not other bundles or the executed/ subdir', function () {
      const otherFile = path.join(tmpDir, 'other-batch.json')
      const executedFile = path.join(tmpDir, 'executed', 'consolidated.json')
      const otherIncorporated = path.join(tmpDir, 'incorporated', 'other-batch')
      fs.writeFileSync(otherFile, '{}')
      fs.mkdirSync(path.dirname(executedFile), { recursive: true })
      fs.writeFileSync(executedFile, '{}')
      fs.mkdirSync(otherIncorporated, { recursive: true })

      claimBundleSlot(tmpDir, 'consolidated')

      expect(fs.existsSync(otherFile)).to.be.true
      expect(fs.existsSync(executedFile)).to.be.true
      expect(fs.existsSync(otherIncorporated)).to.be.true
    })
  })

  describe('TxBuilder.markGatheredFrom', function () {
    it('records source filenames in the saved JSON under _gatheredFrom', function () {
      const builder = new TxBuilder('31337', { outputDir: tmpDir, name: 'consolidated' })
      builder.addTx({ to: '0xa', value: '0', data: '0xaa' })
      builder.markGatheredFrom(['upgrade-A.json', 'upgrade-B.json'])

      const file = builder.saveToFile()
      const contents = JSON.parse(fs.readFileSync(file, 'utf8'))
      expect(contents._gatheredFrom).to.deep.equal(['upgrade-A.json', 'upgrade-B.json'])
    })

    it('saveToFile honors an explicit target path, preserving full enhanced contents', function () {
      const builder = new TxBuilder('31337', { outputDir: tmpDir, name: 'consolidated' })
      builder.addTx({ to: '0xa', value: '0', data: '0xaa' }, { contractName: 'A' })
      builder.markGatheredFrom(['upgrade-A.json'])

      const altPath = path.join(tmpDir, 'executed', 'consolidated.json')
      fs.mkdirSync(path.dirname(altPath), { recursive: true })
      const written = builder.saveToFile(altPath)

      expect(written).to.equal(altPath)
      const contents = JSON.parse(fs.readFileSync(altPath, 'utf8'))
      expect(contents.transactions).to.have.lengthOf(1)
      expect(contents._transactionMetadata).to.deep.equal([{ contractName: 'A' }])
      expect(contents._gatheredFrom).to.deep.equal(['upgrade-A.json'])
    })
  })
})
