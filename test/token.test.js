// helpers
const helpers = require('./lib/testHelpers')
const GraphProtocol = require('../graphProtocol.js')

// contracts
const GraphToken = artifacts.require("./GraphToken.sol")
const MultiSigWallet = artifacts.require("./MultiSigWallet.sol")

// test scope variables
let deployedMultiSigWallet, deployedGraphToken, gp

contract('GraphToken', (accounts) => {
  const initialSupply = 1000000

  before(async () => {

    // deploy the multisig contract
    deployedMultiSigWallet = await MultiSigWallet.new(
      accounts, // owners
      1 // required confirmations
    )
    assert.isObject(deployedMultiSigWallet, "Deploy MultiSigWallet contract.")

    // deploy a contract we can encode a transaction for
    deployedGraphToken = await GraphToken.new(
      deployedMultiSigWallet.address, // governor
      initialSupply // initial supply
    )
    assert.isObject(deployedGraphToken, "Deploy GraphToken contract.")

    // init Graph Protocol JS library with deployed GraphToken contract
    gp = GraphProtocol({
      GraphToken: deployedGraphToken,
      MultiSigWallet: deployedMultiSigWallet
    })
    assert.isObject(gp, "Initialize the Graph Protocol library.")

  })

  describe("totalSupply", () => {
    it("...returns the total amount of tokens", async () => {
      const totalSupply = await deployedGraphToken.totalSupply()
      assert(totalSupply.toNumber() === initialSupply, "Get totalSupply.")
    })
  })

  describe("balanceOf", () => {
    describe("when the requested account has no tokens", () => {
      it("...returns zero", async () => {
        const balanceOf = await deployedGraphToken.balanceOf(accounts[0])
        assert(balanceOf.toNumber() === 0, "Get balanceOf.")
      })
    })

    describe("when the requested account has some tokens", () => {
      it("...returns the total amount of tokens", async () => {
        const governorBalance = await deployedGraphToken.balanceOf(deployedMultiSigWallet.address)
        assert(governorBalance.toNumber() === initialSupply, "Get balanceOf initial holder.")
      })
    })
  })

})
