const Governance = artifacts.require("./Governance.sol")
const Owned = artifacts.require("./Owned.sol")

contract('Governance', accounts => {  

  const originalOwnerAddress = accounts[0]
  const newOwnerAddress = accounts[1]
  const multiSigWalletAddress = originalOwnerAddress // spoof multisig for our testing purposes
  let governanceInstance1, governanceInstance2, ownedInstance1, 
    ownedInstance2, ownedInstance3, ownedInstance4, ownedInstance5

  before(async () => {
    // Init 5 Owned contracts
    ownedInstance1 = await Owned.new()
    ownedInstance2 = await Owned.new()
    ownedInstance3 = await Owned.new()
    ownedInstance4 = await Owned.new()
    ownedInstance5 = await Owned.new()
    const ownedInstances = [
      ownedInstance1.address,
      ownedInstance2.address,
      ownedInstance3.address,
      ownedInstance4.address,
      ownedInstance5.address
    ]

    // Governance contracts are owned by the multisig wallet
    governanceInstance1 = await Governance.new(ownedInstances, multiSigWalletAddress)
    governanceInstance2 = await Governance.new(ownedInstances, multiSigWalletAddress)

    // Set newOwner of Owned instances to Governance1 instance
    await ownedInstance1.transferOwnership(governanceInstance1.address)
    await ownedInstance2.transferOwnership(governanceInstance1.address)
    await ownedInstance3.transferOwnership(governanceInstance1.address)
    await ownedInstance4.transferOwnership(governanceInstance1.address)
    await ownedInstance5.transferOwnership(governanceInstance1.address)

    // Governance1 contract accepts ownership
    await governanceInstance1.acceptOwnershipOfAllContracts()

    console.log(`\tAccount1 (multisigwallet) address: ${originalOwnerAddress}`)
    console.log(`\tAccount2 address: ${newOwnerAddress}`)
    console.log(`\tGovernance1 address: ${governanceInstance1.address}`)
    console.log(`\tGovernance2 address: ${governanceInstance2.address}`)

  })

  it("...should be owned by MultiSigWallet", async () => {
    const owner1 = await governanceInstance1.owner.call()
    const owner2 = await governanceInstance2.owner.call()
    console.log(`\tOwner of Governance1 is ${owner1}`)
    console.log(`\tOwner of Governance2 is ${owner2}`)
    assert(
      owner1 == multiSigWalletAddress &&
      owner2 == multiSigWalletAddress,
      "MultiSigWallet is the owner."
    )
  })

  it("...should be able to transfer ownership of self to Account2", async () => {
    // Transfer ownership
    await governanceInstance1.transferOwnership(newOwnerAddress)
    const newOwner = await governanceInstance1.newOwner.call()
    console.log(`\tPending newOwner of Governance1 is ${newOwner}`)
    assert(newOwner == newOwnerAddress, "Has pending newOwner.")

    // Accept ownership
    await governanceInstance1.acceptOwnership({from: newOwnerAddress})
    const updatedOwner = await governanceInstance1.owner.call()
    assert(updatedOwner == newOwnerAddress, "Has new Owner.")
  })

  it("...should be owned by Account2", async () => {
    const owner = await governanceInstance1.owner.call()
    console.log(`\tUpdated Owner of Governance1 is ${owner}`)
    assert(owner == newOwnerAddress, "Account2 is the owner.")
  })

  it("...should be able to transfer ownership of all contracts to a second Governance contract", async () => {
    // Check owners
    let ownedOwner1 = await ownedInstance1.owner.call()
    let ownedOwner2 = await ownedInstance2.owner.call()
    let ownedOwner3 = await ownedInstance3.owner.call()
    let ownedOwner4 = await ownedInstance4.owner.call()
    let ownedOwner5 = await ownedInstance5.owner.call()
    assert(
      ownedOwner1 == governanceInstance1.address &&
      ownedOwner2 == governanceInstance1.address &&
      ownedOwner3 == governanceInstance1.address &&
      ownedOwner4 == governanceInstance1.address &&
      ownedOwner5 == governanceInstance1.address, 
      "Governance1 is owner of Owned instances"
    )
    console.log(`\tAll Owned contracts are owned by Governance1 ${governanceInstance1.address}`)

    // Transfer ownership
    await governanceInstance1.transferOwnershipOfAllContracts(governanceInstance2.address, {from: newOwnerAddress})
    
    // Accept ownership
    await governanceInstance2.acceptOwnershipOfAllContracts()
    ownedOwner1 = await ownedInstance1.owner.call()
    ownedOwner2 = await ownedInstance2.owner.call()
    ownedOwner3 = await ownedInstance3.owner.call()
    ownedOwner4 = await ownedInstance4.owner.call()
    ownedOwner5 = await ownedInstance5.owner.call()
    assert(
      ownedOwner1 == governanceInstance2.address &&
      ownedOwner2 == governanceInstance2.address &&
      ownedOwner3 == governanceInstance2.address &&
      ownedOwner4 == governanceInstance2.address &&
      ownedOwner5 == governanceInstance2.address, 
      "Governance2 is owner of Owned instances"
    )
    console.log(`\tAll Owned contracts are owned by Governance2 ${governanceInstance2.address}`)

  })

})

/*
  Next steps:
    - Init 5 Owned instances and transfer ownership to a new governance contract
*/
