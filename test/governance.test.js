const Governance = artifacts.require("./Governance.sol")
const GovernanceCopy = artifacts.require("./GovernanceCopy.sol")
const MultiSigWallet = artifacts.require("./MultiSigWallet.sol")

const address0 = 0x0000000000000000000000000000000000000000,
      testData = 0x7b2022617272617941223a205b312c20322c20335d207d

let multiSigAddress

// contract('MultiSigWallet', accounts => {

//   it("...should have an address", () => {
//     return MultiSigWallet.deployed()
//     .then(instance => instance.contractAddress.call())
//     .then(contractAddress => {
//       multiSigAddress = contractAddress
//       assert(multiSigAddress, "Has address.")
//     })
//   })

//   it("...should have owners", () => {
//     return MultiSigWallet.deployed()
//     .then(instance => instance.getOwners.call())
//     .then((owners) => {
//       assert(owners.length > 0, `Has owners.`)
//     })
//   })

//   it("...should have no transactions", () => {
//     return MultiSigWallet.deployed()
//     .then(instance => instance.getTransactionCount.call(false, false))
//     .then(transactionCount => {
//       assert(transactionCount == 0, "Has no transactions.")
//     })
//   })

// })

contract('MultiSigWallet', accounts => {

  let instance

  it("...should have an address", async () => {
    instance = await MultiSigWallet.deployed()
    const contractAddress = await instance.contractAddress.call()
    multiSigAddress = contractAddress
    return assert(multiSigAddress, "Has address.")
  })

  it("...should have owners", async () => {
    const owners = await instance.getOwners.call()
    assert(owners.length > 0, `Has owners.`)
  })

  it("...should have no transactions", async () => {
    const transactionCount = await instance.getTransactionCount.call(false, false)
    assert(transactionCount == 0, "Has no transactions.")
  })

})

/* This doesn't work because the addTransaction function is internal */
/* The multisig is probably supposed to be inherited? */
// contract('MultiSigWallet', accounts => {
//   it("...should submit transaction", () => {
//     return MultiSigWallet.deployed()
//     .then(instance => instance.addTransaction.call(
//       multiSigAddress, // destination
//       0, // value
//       testData // data
//     ))
//     .then(transactionId => {
//       assert(transactionId, "Transaction was created.")
//     })
//   })
// })

contract('Governance', accounts => {

  it("...should be owned by MultiSigWallet", async () => {
    const instance = await Governance.deployed()
    const owner = await instance.owner.call()
    assert(owner == multiSigAddress, "MultiSigWallet is the owner.")
  })

})

contract('GovernanceCopy', accounts => {

  let instance

  it("...should have owner", async () => {
    instance = await GovernanceCopy.deployed()
    const owner = await instance.owner.call()
    console.log(`\tOwner of GovernanceCopy is ${owner}`)
    assert(owner, "Has owner.")
  })

  it("...should NOT be owned by MultiSigWallet", async () => {
    const owner = await instance.owner.call()
    assert(owner != multiSigAddress, "MultiSigWallet is the owner.")
  })

  it("...should have address", async () => {
    const senderAddress = await instance.senderAddress.call()
    console.log(`\tAddress of sender is ${senderAddress}`)
    assert(senderAddress, "senderAddress exists")
    const contractAddress = await instance.contractAddress.call()
    console.log(`\tAddress of GovernanceCopy is ${contractAddress}`)
    assert(contractAddress, "contractAddress exists")
  })

  it("...should be able to transfer ownership of self", async () => {
    await instance.transferOwnership.call(multiSigAddress)
    const newOwner = await instance.newOwner.call()
    console.log(`\tPending newOwner of GovernanceCopy is ${newOwner}`)
    assert(newOwner == multiSigAddress, "Has pending newOwner.")
  })
})

