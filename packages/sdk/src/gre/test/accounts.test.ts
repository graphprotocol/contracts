import chai, { expect } from 'chai'
import chaiAsPromised from 'chai-as-promised'
import { ethers } from 'ethers'
import { useEnvironment } from './helpers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

import type { AccountNames, GraphRuntimeEnvironment } from '../types'

chai.use(chaiAsPromised)

const mnemonic = 'pumpkin orient can short never warm truth legend cereal tourist craft skin'

describe('GRE usage > account management', function () {
  // Tests that loop through all the wallets take more than the default timeout
  this.timeout(10_000)

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
        await expect(wallet.signMessage('test')).to.eventually.be.fulfilled
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
        await expect(wallet.signMessage('test')).to.eventually.be.fulfilled
      }
    })

    it('should return wallet not connected to a provider', async function () {
      for (let i = 0; i < 20; i++) {
        const derived = ethers.Wallet.fromMnemonic(mnemonic, `m/44'/60'/0'/0/${i}`)
        const wallet = await graph.getWallet(derived.address)
        expect(wallet.provider).to.be.null
      }
    })

    it('should throw if provided address cant be derived from mnemonic', async function () {
      const getWallet = graph.getWallet('0x0000000000000000000000000000000000000000')
      await expect(getWallet).to.eventually.be.rejectedWith(/Could not find wallet for address: /)
    })
  })
})

describe('GRE usage > secure accounts', function () {
  useEnvironment('graph-config', 'hardhat')

  let graph: GraphRuntimeEnvironment
  let graphSecureAccounts: GraphRuntimeEnvironment

  beforeEach(function () {
    graph = this.hre.graph({
      disableSecureAccounts: true,
    })

    graphSecureAccounts = this.hre.graph({
      disableSecureAccounts: false,
      l1AccountName: 'test-account',
      l1AccountPassword: 'batman-with-cheese',
      l2AccountName: 'test-account-l2',
      l2AccountPassword: 'batman-with-cheese',
    })
  })

  describe('getDeployer', function () {
    it('should return different accounts', async function () {
      const deployer = await graph.l1!.getDeployer()
      const deployerSecureAccount = await graphSecureAccounts.l1!.getDeployer()

      expect(deployer.address).not.to.equal(deployerSecureAccount.address)
      expect(deployer.address).to.equal('0x2770fb12b368a9aBf4A02DB34B0F6057fC03BD0d')
      expect(deployerSecureAccount.address).to.equal('0xC108fda1b5b2903751594298769Efd4904b146bD')
    })

    it('should return accounts capable of signing messages', async function () {
      const deployer = await graph.l1!.getDeployer()
      const deployerSecureAccount = await graphSecureAccounts.l1!.getDeployer()

      await expect(deployer.signMessage('test')).to.eventually.be.fulfilled
      await expect(deployerSecureAccount.signMessage('test')).to.eventually.be.fulfilled
    })
  })

  describe('getNamedAccounts', function () {
    it('should return the same accounts', async function () {
      const accounts = await graph.l1!.getNamedAccounts()
      const secureAccounts = await graphSecureAccounts.l1!.getNamedAccounts()

      const accountNames = Object.keys(accounts) as AccountNames[]
      const secureAccountNames = Object.keys(secureAccounts)

      expect(accountNames.length).to.equal(secureAccountNames.length)

      for (const name of accountNames) {
        const account = accounts[name]
        const secureAccount = secureAccounts[name]

        expect(account.address).to.equal(secureAccount.address)
      }
    })

    it('should return accounts incapable of signing messages', async function () {
      const accounts = await graph.l1!.getNamedAccounts()
      const secureAccounts = await graphSecureAccounts.l1!.getNamedAccounts()

      const accountNames = Object.keys(accounts) as AccountNames[]

      for (const name of accountNames) {
        const account = accounts[name]
        const secureAccount = secureAccounts[name]

        await expect(account.signMessage('test')).to.eventually.be.rejectedWith(/unknown account/)
        await expect(secureAccount.signMessage('test')).to.eventually.be.rejected
        const tx = account.sendTransaction({
          to: ethers.constants.AddressZero,
          value: ethers.utils.parseEther('0'),
        })
        await expect(tx).to.eventually.be.rejected
      }
    })
  })

  describe('getTestAccounts', function () {
    it('should return different accounts', async function () {
      const accounts = await graph.l1!.getTestAccounts()
      const secureAccounts = await graphSecureAccounts.l1!.getTestAccounts()

      expect(accounts.length).to.equal(secureAccounts.length)

      for (let i = 0; i < accounts.length; i++) {
        expect(accounts[i].address).not.to.equal(secureAccounts[i].address)
      }
    })

    it('should return accounts capable of signing messages', async function () {
      const accounts = await graph.l1!.getTestAccounts()
      const secureAccounts = await graphSecureAccounts.l1!.getTestAccounts()

      for (let i = 0; i < accounts.length; i++) {
        await expect(accounts[i].signMessage('test')).to.eventually.be.fulfilled
        await expect(secureAccounts[i].signMessage('test')).to.eventually.be.fulfilled
      }
    })
  })
})

describe('GRE usage > fork', function () {
  useEnvironment('graph-config', 'hardhat')

  let graph: GraphRuntimeEnvironment

  beforeEach(function () {
    graph = this.hre.graph({
      fork: true,
    })
  })
  describe('getNamedAccounts', function () {
    it('should allow impersonating named accounts', async function () {
      const accounts = await graph.l1!.getNamedAccounts()
      const secureAccounts = await graph.l1!.getNamedAccounts()

      const accountNames = Object.keys(accounts) as AccountNames[]

      for (const name of accountNames) {
        const account: SignerWithAddress = accounts[name]
        const secureAccount: SignerWithAddress = secureAccounts[name]

        await expect(account.signMessage('test')).to.eventually.be.rejectedWith(/unknown account/)
        await expect(secureAccount.signMessage('test')).to.eventually.be.rejected

        const tx = account.sendTransaction({
          to: ethers.constants.AddressZero,
          value: ethers.utils.parseEther('0'),
        })
        await expect(tx).to.eventually.be.fulfilled
      }
    })
  })
})
