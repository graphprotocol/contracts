import chai, { expect } from 'chai'
import chaiAsPromised from 'chai-as-promised'
import { ethers } from 'ethers'
import { GraphRuntimeEnvironment } from '../type-extensions'
import { useEnvironment } from './helpers'

chai.use(chaiAsPromised)

const mnemonic = 'pumpkin orient can short never warm truth legend cereal tourist craft skin'

describe('GRE usage > account management', function () {
  useEnvironment('graph-config', 'hardhat')

  let graph: GraphRuntimeEnvironment

  beforeEach(function () {
    graph = this.hre.graph()
  })

  describe('getWallets', function () {
    it('should return 20 wallets', async function () {
      const wallets = await graph.getWallets()
      expect(wallets.length).to.equal(20)
    })

    it('should derive wallets from hardhat config mnemonic', async function () {
      const wallets = await graph.getWallets()

      for (let i = 0; i < wallets.length; i++) {
        const derived = ethers.Wallet.fromMnemonic(mnemonic, `m/44'/60'/0'/0/${i}`)
        expect(wallets[i].address).to.equal(derived.address)
      }
    })

    it('should return wallets capable of signing messages', async function () {
      const wallets = await graph.getWallets()

      for (const wallet of wallets) {
        expect(wallet.signMessage('test')).to.eventually.be.fulfilled
      }
    })

    it('should return wallets not connected to a provider', async function () {
      const wallets = await graph.getWallets()

      for (const wallet of wallets) {
        expect(wallet.provider).to.be.null
      }
    })
  })

  describe('getWallet', function () {
    it('should return wallet if provided address can be derived from mnemonic', async function () {
      for (let i = 0; i < 20; i++) {
        const derived = ethers.Wallet.fromMnemonic(mnemonic, `m/44'/60'/0'/0/${i}`)
        const wallet = await graph.getWallet(derived.address)
        expect(wallet.address).to.equal(derived.address)
      }
    })

    it('should return wallet capable of signing messages', async function () {
      for (let i = 0; i < 20; i++) {
        const derived = ethers.Wallet.fromMnemonic(mnemonic, `m/44'/60'/0'/0/${i}`)
        const wallet = await graph.getWallet(derived.address)
        expect(wallet.signMessage('test')).to.eventually.be.fulfilled
      }
    })

    it('should return wallet not connected to a provider', async function () {
      for (let i = 0; i < 20; i++) {
        const derived = ethers.Wallet.fromMnemonic(mnemonic, `m/44'/60'/0'/0/${i}`)
        const wallet = await graph.getWallet(derived.address)
        expect(wallet.provider).to.be.null
      }
    })

    it('should return undefined if provided address cant be derived from mnemonic', async function () {
      const wallet = await graph.getWallet('0x0000000000000000000000000000000000000000')
      expect(wallet).to.be.undefined
    })
  })
})
