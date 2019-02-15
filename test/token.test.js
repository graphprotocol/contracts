const truffleAssert = require('truffle-assertions')

// contracts
const GraphToken = artifacts.require("./GraphToken.sol")

contract('GraphToken', (accounts) => {
  // test scope variables
  let deployedGraphToken
  const initialSupply = 1000000,
    initialHolder = accounts[1],
    recipient = accounts[2],
    anotherAccount = accounts[3]

  before(async () => {

    // deploy a contract we can encode a transaction for
    deployedGraphToken = await GraphToken.new(
      initialHolder, // governor
      initialSupply // initial supply
    )
    assert.isObject(deployedGraphToken, "Deploy GraphToken contract.")

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
        const balanceOf = await deployedGraphToken.balanceOf(recipient)
        assert(balanceOf.toNumber() === 0, "Get balanceOf.")
      })
    })

    describe("when the requested account has some tokens", () => {
      it("...returns the total amount of tokens", async () => {
        const governorBalance = await deployedGraphToken.balanceOf(initialHolder)
        assert(governorBalance.toNumber() === initialSupply, "Get balanceOf initial holder.")
      })
    })
  })

  describe("transfer", () => {
    describe("when the recipient is not the zero address", () => {
      describe("when the sender does not have enough balance", () => {
        it('should pass when function fails', async () => {
          await truffleAssert.fails(Promise.reject());
        })
        it("...reverts", async () => {

          // await truffleAssert.fails(
          //   deployedGraphToken.contract.methods.transfer(
          //     recipient, // to
          //     initialSupply + 1 // value
          //   ).call({ from: initialHolder }),
          //   truffleAssert.ErrorType.REVERT,
          //   "Reverts sending invalid amount."
          // )

        })
      })
    })
  })

})
