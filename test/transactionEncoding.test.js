// helpers
const GraphProtocol = require('../graphProtocol.js')

// contracts
const ServiceRegistry = artifacts.require("./ServiceRegistry.sol")

// test scope variables
let deployedServiceRegistry, gp

contract('NPM Module', ([deployment, governor, ...accounts]) => {
  
  before(async () => {

    // deploy a contract we can encode a transaction for
    deployedServiceRegistry = await ServiceRegistry.new(
      governor, // governor
      { from: deployment }
    )
    assert.isObject(deployedServiceRegistry, "Deploy ServiceRegistry contract.")

    // init Graph Protocol JS library with deployed ServiceRegistry contract
    gp = GraphProtocol({
      ServiceRegistry: deployedServiceRegistry
    })
    assert.isObject(gp, "Initialize the Graph Protocol library.")

  })

  it("...should allow using graphProtocol.js to encode ABI transaction data", async () => {
    const serviceProvider = accounts[0]
    const urlToRegister = accounts[1]

    // encode transaction data using encodeABI()
    const directlyEncodedAbiTxData = deployedServiceRegistry.contract.methods.setUrl(
      serviceProvider, // <address> serviceProvider
      urlToRegister // <bytes> url
    ).encodeABI()
    assert(directlyEncodedAbiTxData.length, "Transaction data encoded via encodeABI.")

    // encode transaction data using graphProtocol.js
    const moduleEncodedTxData = gp.abiEncode(
      deployedServiceRegistry.contract.methods.setUrl,
      [
        serviceProvider, // <address> serviceProvider
        urlToRegister // <bytes> url
      ]
    )
    assert(moduleEncodedTxData.length, "Transaction data encoded via gp.abiEncode.")

    // both methods should return the same data
    assert(moduleEncodedTxData === directlyEncodedAbiTxData, "JS library encodes ABI transaction data.")
    
  })
  
})
