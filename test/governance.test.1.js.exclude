const Governance = artifacts.require("./Governance.sol")
const Owned = artifacts.require("./Owned.sol")

contract('Governance', accounts => {  

  const originalOwnerAddress = accounts[0]
  const newOwnerAddress = accounts[1]
  const multiSigWalletAddress = originalOwnerAddress // spoof multisig for our testing purposes
  let governanceInstances = new Array(2)
  let ownedInstances = new Array(5)

  before(async () => {
    // Init 5 Owned contracts
    ownedInstances[0] = await Owned.new()
    ownedInstances[1] = await Owned.new()
    ownedInstances[2] = await Owned.new()
    ownedInstances[3] = await Owned.new()
    ownedInstances[4] = await Owned.new()
    const ownedInstanceAddresses = [
      ownedInstances[0].address,
      ownedInstances[1].address,
      ownedInstances[2].address,
      ownedInstances[3].address,
      ownedInstances[4].address
    ]

    // Governance contracts are owned by the multisig wallet
    governanceInstances[0] = await Governance.new(ownedInstanceAddresses, multiSigWalletAddress)
    governanceInstances[1] = await Governance.new(ownedInstanceAddresses, multiSigWalletAddress)

    // Set newOwner of Owned instances to Governance1 instance
    await ownedInstances[0].transferOwnership(governanceInstances[0].address)
    await ownedInstances[1].transferOwnership(governanceInstances[0].address)
    await ownedInstances[2].transferOwnership(governanceInstances[0].address)
    await ownedInstances[3].transferOwnership(governanceInstances[0].address)
    await ownedInstances[4].transferOwnership(governanceInstances[0].address)

    // Governance1 contract accepts ownership
    await governanceInstances[0].acceptOwnershipOfAllContracts()

    console.log(`\tAccount1 (multisigwallet) address: ${originalOwnerAddress}`)
    console.log(`\tAccount2 address: ${newOwnerAddress}`)
    console.log(`\tGovernance1 address: ${governanceInstances[0].address}`)
    console.log(`\tGovernance2 address: ${governanceInstances[1].address}`)
  })

  it("...should be owned by MultiSigWallet", async () => {
    const owner1 = await governanceInstances[0].owner.call()
    const owner2 = await governanceInstances[1].owner.call()
    assert(
      owner1 == multiSigWalletAddress &&
      owner2 == multiSigWalletAddress,
      "MultiSigWallet is the owner."
    )
    console.log(`\tOwner of Governance1 is ${owner1}`)
    console.log(`\tOwner of Governance2 is ${owner2}`)
  })

  it("...should be able to transfer ownership of self to Account2", async () => {
    // Transfer ownership
    await governanceInstances[0].transferOwnership(newOwnerAddress)
    const newOwner = await governanceInstances[0].newOwner.call()
    assert(newOwner == newOwnerAddress, "Has pending newOwner.")
    console.log(`\tPending newOwner of Governance1 is ${newOwner}`)
  })

  it("...should be owned by Account2 when accepted", async () => {
    // Accept ownership
    await governanceInstances[0].acceptOwnership({from: newOwnerAddress})
    const updatedOwner = await governanceInstances[0].owner.call()
    assert(updatedOwner == newOwnerAddress, "Has new Owner.")
    console.log(`\tUpdated Owner of Governance1 is ${updatedOwner}`)
  })

  it("...should be able to transfer ownership of all contracts to a second Governance contract", async () => {
    // Check owners
    let ownedOwner1 = await ownedInstances[0].owner.call()
    let ownedOwner2 = await ownedInstances[1].owner.call()
    let ownedOwner3 = await ownedInstances[2].owner.call()
    let ownedOwner4 = await ownedInstances[3].owner.call()
    let ownedOwner5 = await ownedInstances[4].owner.call()
    assert(
      ownedOwner1 == governanceInstances[0].address &&
      ownedOwner2 == governanceInstances[0].address &&
      ownedOwner3 == governanceInstances[0].address &&
      ownedOwner4 == governanceInstances[0].address &&
      ownedOwner5 == governanceInstances[0].address, 
      "Governance1 is owner of Owned instances"
    )
    console.log(`\tAll Owned contracts are owned by Governance1 ${governanceInstances[0].address}`)

    // Transfer ownership
    await governanceInstances[0].transferOwnershipOfAllContracts(governanceInstances[1].address, {from: newOwnerAddress})
    
    // Accept ownership
    await governanceInstances[1].acceptOwnershipOfAllContracts()
    ownedOwner1 = await ownedInstances[0].owner.call()
    ownedOwner2 = await ownedInstances[1].owner.call()
    ownedOwner3 = await ownedInstances[2].owner.call()
    ownedOwner4 = await ownedInstances[3].owner.call()
    ownedOwner5 = await ownedInstances[4].owner.call()
    assert(
      ownedOwner1 == governanceInstances[1].address &&
      ownedOwner2 == governanceInstances[1].address &&
      ownedOwner3 == governanceInstances[1].address &&
      ownedOwner4 == governanceInstances[1].address &&
      ownedOwner5 == governanceInstances[1].address, 
      "Governance2 is owner of Owned instances"
    )
    console.log(`\tAll Owned contracts have been transferred to Governance2 ${governanceInstances[1].address}`)
  })

})
