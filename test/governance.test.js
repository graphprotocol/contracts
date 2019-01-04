const Governance = artifacts.require("./Governance.sol")
const GovernanceCopy = artifacts.require("./GovernanceCopy.sol")
const MultiSigWallet = artifacts.require("./MultiSigWallet.sol")

const address0 = 0x0000000000000000000000000000000000000000,
      testData = 0x7ba20202020227465737464617461223a205b312c20322c20335da7d

let multiSigAddress

contract('MultiSigWallet', accounts => {
  it("...should have an address", () => {
    return MultiSigWallet.deployed()
    .then(instance => instance.contractAddress.call())
    .then(contractAddress => {
      multiSigAddress = contractAddress
      assert(multiSigAddress, "Has address.")
    })
  })
})

contract('MultiSigWallet', accounts => {
  it("...should have owners", () => {
    return MultiSigWallet.deployed()
    .then(instance => instance.getOwners.call())
    .then((owners) => {
      assert(owners.length > 0, `Has owners.`)
    })
  })
})

contract('MultiSigWallet', accounts => {
  it("...should have no transactions", () => {
    return MultiSigWallet.deployed()
    .then(instance => instance.getTransactionCount.call(false, false))
    .then(transactionCount => {
      assert(transactionCount == 0, "Has no transactions.")
    })
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
  it("...should have owner", () => {
    return Governance.deployed()
    .then(instance => instance.owner.call())
    .then(owner => {
      assert(owner, "Has owner.")
    })
  })
})

contract('Governance', accounts => {
  it("...should be owned by MultiSigWallet", () => {
    return Governance.deployed()
    .then(instance => instance.owner.call())
    .then(owner => {
      assert(owner == multiSigAddress, "MultiSigWallet is the owner.")
    })
  })
})

contract('GovernanceCopy', accounts => {
  it("...should have owner", () => {
    return GovernanceCopy.deployed()
    .then(instance => instance.owner.call())
    .then(owner => {
      console.log(`\tOwner of GovernanceCopy is ${owner}`)
      assert(owner, "Has owner.")
    })
  })
})

contract('GovernanceCopy', accounts => {
  it("...should NOT be owned by MultiSigWallet", () => {
    return GovernanceCopy.deployed()
    .then(instance => instance.owner.call())
    .then(owner => {
      assert(owner != multiSigAddress, "MultiSigWallet is the owner.")
    })
  })
})

contract('GovernanceCopy', accounts => {
  it("...should have address", () => {
    let instance
    return GovernanceCopy.deployed()
    .then(i => {instance = i})
    .then(() => instance.senderAddress.call())
    .then(senderAddress => {
      console.log(`\tAddress of sender is ${senderAddress}`)
      assert(senderAddress, "senderAddress")
    })
    .then(() => instance.contractAddress.call())
    .then(contractAddress => {
      console.log(`\tAddress of GovernanceCopy is ${contractAddress}`)
      assert(contractAddress, "contractAddress")
    })
  })
})

contract('GovernanceCopy', accounts => {
  it("...should be able to transfer ownership of self", () => {
    let instance
    return GovernanceCopy.deployed()
    .then(i => {instance = i})
    .then(() => instance.transferOwnership.call(multiSigAddress))
    .then(() => instance.newOwner.call())
    .then(newOwner => {
      console.log(`\tPending newOwner of GovernanceCopy is ${newOwner}`)
      assert(newOwner == multiSigAddress, "Has pending newOwner.")
    })
  })
})

