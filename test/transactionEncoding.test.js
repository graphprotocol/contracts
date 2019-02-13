// helpers
const GraphProtocol = require('./lib/graphProtocol.js')

// contracts
const Staking = artifacts.require("./Staking.sol")

// test scope variables
let deployedStaking, gp

contract('NPM Module', accounts => {
  
  before(async () => {

    // deploy a contract we can encode a transaction for
    deployedStaking = await Staking.new(
      accounts[0] // governor
    )
    assert.isObject(deployedStaking, "Deploy Staking contract.")

    // init Graph Protocol JS library with deployed staking contract
    gp = GraphProtocol({
      Staking: deployedStaking
    })
    assert.isObject(gp, "Initialize the Graph Protocol library.")

  })

  it("...should allow using graphProtocol.js to encode ABI transaction data", async () => {

    // encode transaction data using encodeABI()
    const directlyEncodedAbiTxData = deployedStaking.contract.methods.setMinimumCurationStakingAmount(
      100, // amount
    ).encodeABI()
    assert(directlyEncodedAbiTxData.length, "Transaction data encoded via encodeABI.")

    // encode transaction data using graphProtocol.js
    const moduleEncodedTxData = gp.abiEncode(
      deployedStaking.contract.methods.setMinimumCurationStakingAmount,
      [
        100, // amount
      ]
    )
    assert(moduleEncodedTxData.length, "Transaction data encoded via gp.abiEncode.")

    // both methods should return the same data
    assert(moduleEncodedTxData === directlyEncodedAbiTxData, "JS library encodes ABI transaction data.")
    
  })
  
})
