// import { expect } from 'chai'
// import hre, { upgrades } from 'hardhat'
// import '@nomiclabs/hardhat-ethers'

// const { ethers } = hre

// // Deploy the first version of Staking along with a Proxy
// const deployStaking = async (contractName: string): Promise<string> => {
//   // Library
//   const LibCobbDouglasFactory = await ethers.getContractFactory('LibCobbDouglas')
//   const libCobbDouglas = await LibCobbDouglasFactory.deploy()

//   // Deploy contract with Proxy
//   const Staking = await ethers.getContractFactory(contractName, {
//     libraries: {
//       LibCobbDouglas: libCobbDouglas.address,
//     },
//   })
//   const instance = await upgrades.deployProxy(Staking, {
//     initializer: false,
//     unsafeAllowLinkedLibraries: true,
//   })
//   return instance.address
// }

// // Deploy an upgrade
// const upgradeStaking = async (proxyAddress: string, contractName: string): Promise<string> => {
//   // Library
//   const LibCobbDouglasFactory = await ethers.getContractFactory('LibCobbDouglas')
//   const libCobbDouglas = await LibCobbDouglasFactory.deploy()

//   // Upgrade contract
//   const StakingImpl = await ethers.getContractFactory(contractName, {
//     libraries: {
//       LibCobbDouglas: libCobbDouglas.address,
//     },
//   })
//   const upgraded = await upgrades.prepareUpgrade(proxyAddress, StakingImpl, {
//     unsafeAllowLinkedLibraries: true,
//   })
//   return upgraded
// }

// describe('Upgrade', () => {
//   describe('Test compatible layout', function () {
//     it('Staking', async function () {
//       // const proxyAddress = await deployStaking('StakingV1')
//       // await upgradeStaking(proxyAddress, 'Staking')
//     })
//   })
// })
