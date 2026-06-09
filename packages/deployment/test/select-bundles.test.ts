import { expect } from 'chai'

import { selectBundles } from '../lib/execute-governance.js'

describe('selectBundles', function () {
  describe('no name, no --all', function () {
    it('returns no-op when no files are available', function () {
      expect(selectBundles([])).to.deep.equal({ kind: 'no-op' })
    })

    it('executes the single available bundle implicitly', function () {
      expect(selectBundles(['gip-0088-upgrades.json'])).to.deep.equal({
        kind: 'execute',
        files: ['gip-0088-upgrades.json'],
      })
    })

    it('errors when 2+ files are available, listing the conflicting set', function () {
      const result = selectBundles(['gip-0088-upgrades.json', 'upgrade-HorizonStaking.json'])
      expect(result).to.deep.equal({
        kind: 'error',
        code: 'multi-no-flag',
        files: ['gip-0088-upgrades.json', 'upgrade-HorizonStaking.json'],
      })
    })
  })

  describe('--all', function () {
    it('executes every pending bundle when 2+ files exist', function () {
      const files = ['gip-0088-upgrades.json', 'upgrade-HorizonStaking.json']
      expect(selectBundles(files, { all: true })).to.deep.equal({
        kind: 'execute',
        files,
      })
    })

    it('still no-ops when no files are available', function () {
      expect(selectBundles([], { all: true })).to.deep.equal({ kind: 'no-op' })
    })
  })

  describe('--name X', function () {
    it('executes the matching bundle when X.json exists', function () {
      const result = selectBundles(['gip-0088-upgrades.json', 'upgrade-HorizonStaking.json'], {
        name: 'upgrade-HorizonStaking',
      })
      expect(result).to.deep.equal({ kind: 'execute', files: ['upgrade-HorizonStaking.json'] })
    })

    it('errors when X.json is missing (default)', function () {
      const result = selectBundles(['gip-0088-upgrades.json'], { name: 'upgrade-Missing' })
      expect(result).to.deep.equal({ kind: 'error', code: 'name-missing', targetFile: 'upgrade-Missing.json' })
    })

    it('no-ops when X.json is missing and --allow-missing is set', function () {
      const result = selectBundles(['gip-0088-upgrades.json'], { name: 'upgrade-Missing', allowMissing: true })
      expect(result).to.deep.equal({ kind: 'no-op' })
    })
  })

  describe('--name X AND --all', function () {
    it('errors as mutually exclusive even when files would match', function () {
      const result = selectBundles(['gip-0088-upgrades.json'], { name: 'gip-0088-upgrades', all: true })
      expect(result).to.deep.equal({ kind: 'error', code: 'name-and-all' })
    })

    it('errors as mutually exclusive even when files are empty', function () {
      const result = selectBundles([], { name: 'gip-0088-upgrades', all: true })
      expect(result).to.deep.equal({ kind: 'error', code: 'name-and-all' })
    })
  })
})
