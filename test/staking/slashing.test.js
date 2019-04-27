const { expectEvent, shouldFail } = require('openzeppelin-test-helpers');

// contracts
const GraphToken = artifacts.require("./GraphToken.sol")
const Staking = artifacts.require("./Staking.sol")

// helpers
const GraphProtocol = require('../../graphProtocol.js')
const helpers = require('../lib/testHelpers')

contract('Staking (Slashing)', ([
  deploymentAddress,
  daoContract,
  indexingStaker,
  fisherman,
  ...accounts
]) => {
  /** 
   * testing constants
   */
  const minimumCurationStakingAmount = 100,
    defaultReserveRatio = 500000, // PPM
    minimumIndexingStakingAmount = 100,
    maximumIndexers = 10,
    slashingPercent = 10,
    coolingPeriod = 60 * 60 * 24 * 7, // seconds
    chainId = 1,
    domainTypeHash = web3.utils.sha3("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"),
    domainNameHash = web3.utils.sha3("Graph Protocol"),
    domainVersionHash = web3.utils.sha3("0.1"),
    attestationTypeHash = web3.utils.sha3("Attestation(bytes32 subgraphId,IpfsHash requestCID,IpfsHash responseCID,uint256 gasUsed,uint256 responseNumBytes)IpfsHash(bytes32 hash,uint16 hashFunction)"),
    attestationByteSize = 197
  let deployedStaking,
    deployedGraphToken,
    initialTokenSupply = 1000000,
    stakingAmount = 1000,
    tokensMintedForStaker = stakingAmount * 10,
    subgraphIdHex0x = helpers.randomSubgraphIdHex0x(),
    subgraphIdHex = helpers.randomSubgraphIdHex(subgraphIdHex0x),
    subgraphIdBytes = helpers.randomSubgraphIdBytes(subgraphIdHex),
    gp

  before(async () => {
    // deploy GraphToken contract
    deployedGraphToken = await GraphToken.new(
      daoContract, // governor
      initialTokenSupply, // initial supply
      { from: deploymentAddress }
    )
    assert.isObject(deployedGraphToken, "Deploy GraphToken contract.")

    // send some tokens to the staking account
    const tokensForIndexer = await deployedGraphToken.mint(
      indexingStaker, // to
      tokensMintedForStaker, // value
      { from: daoContract }
    )
    assert(tokensForIndexer, "Mints Graph Tokens for Indexer.")

    // deploy Staking contract
    deployedStaking = await Staking.new(
      daoContract, // <address> governor
      minimumCurationStakingAmount, // <uint256> minimumCurationStakingAmount
      defaultReserveRatio, // <uint256> defaultReserveRatio (ppm)
      minimumIndexingStakingAmount, // <uint256> minimumIndexingStakingAmount
      maximumIndexers, // <uint256> maximumIndexers
      slashingPercent, // <uint256> slashingPercent
      coolingPeriod, // <uint256> coolingPeriod
      deployedGraphToken.address, // <address> token
      { from: deploymentAddress }
    )
    assert.isObject(deployedStaking, "Deploy Staking contract.")
    assert(web3.utils.isAddress(deployedStaking.address), "Staking address is address.")

    // init Graph Protocol JS library with deployed staking contract
    gp = GraphProtocol({
      Staking: deployedStaking,
      GraphToken: deployedGraphToken
    })
    assert.isObject(gp, "Initialize the Graph Protocol library.")
  })

  describe("slashing", () => {
    it('...should allow staking for indexing', async () => {
      let totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
      let stakerBalance = await deployedGraphToken.balanceOf(indexingStaker)
      assert(
        stakerBalance.toNumber() === tokensMintedForStaker && 
        totalBalance.toNumber() === 0,
        "Balances before transfer are correct."
      )

      // stake for indexing
      const data = web3.utils.hexToBytes('0x00' + subgraphIdHex)
      const indexingStake = await deployedGraphToken.transferWithData(
        deployedStaking.address, // to
        stakingAmount, // value
        data, // data
        { from: indexingStaker }
      )
      assert(indexingStake, "Stake Graph Tokens for indexing directly.")

      const { amountStaked, logoutStarted } = await gp.staking.indexingNodes(
        indexingStaker,
        subgraphIdBytes
      )
      assert(
        amountStaked.toNumber() === stakingAmount &&
        logoutStarted.toNumber() === 0,
        "Staked indexing amount confirmed."
      )
      
      totalBalance = await deployedGraphToken.balanceOf(deployedStaking.address)
      stakerBalance = await deployedGraphToken.balanceOf(indexingStaker)
      assert(
        stakerBalance.toNumber() === tokensMintedForStaker - stakingAmount && 
        totalBalance.toNumber() === stakingAmount,
        "Balances after transfer are correct."
      )
    })
  
    it('...should allow a dispute to be created', async () => {
      const data = await createDisputeDataWithSignedAttestation()
      const createDispute = await deployedGraphToken.transferWithData(
        deployedStaking.address, // to
        0, // value
        data, // data
        { from: fisherman }
      )
      assert.isObject(createDispute, "Creating dispute.")
      console.log({ createDispute })
    })
  })

  async function createDisputeDataWithSignedAttestation() {
    const attestationData = {
      subgraphId: subgraphIdHex0x,
      requestCID: {
        hash: web3.utils.randomHex(32),
        hashFunction: '0x1220'
      },
      responseCID: {
        hash: web3.utils.randomHex(32),
        hashFunction: '0x1220'
      },
      gasUsed: 123000, // Math.floor(Math.random() * 100000) + 100000,
      responseBytes: 4500 // Math.floor(Math.random() * 3000) + 1000
    }
    const domainSeparator = web3.utils.sha3(
      domainTypeHash +
      domainNameHash +
      domainVersionHash +
      chainId +
      deployedStaking.address +
      subgraphIdHex0x
    )
    const encodedAttestation = web3.eth.abi.encodeParameters(
      [
        "bytes32",
        "bytes32",
        "uint16",
        "bytes32",
        "uint16",
        "uint256",
        "uint256"
      ],
      [
        attestationData.subgraphId,
        attestationData.requestCID.hash,
        attestationData.requestCID.hashFunction,
        attestationData.responseCID.hash,
        attestationData.responseCID.hashFunction,
        attestationData.gasUsed,
        attestationData.responseBytes
      ]
    )
    const attestationHash = web3.utils.sha3(
      attestationTypeHash + 
      encodedAttestation
    )
    const signedAttestation = await web3.eth.sign(
      domainSeparator + attestationHash,
      fisherman
    )
    // required bytes: 1 + 32 + 197 = 230
    const tokensReceivedHexData = '0x'
      + '02' // TokenReceiptAction.dispute (1 byte)
      + subgraphIdHex // Subgraph ID without `0x` (32 bytes)
      + encodedAttestation.substring(2) // Hex encoded attestation w/o `0x` (< 197 bytes)
      + signedAttestation.substring(2) // IEP712 domain separator signed attestation (< 197 bytes)
    const data = web3.utils.hexToBytes( tokensReceivedHexData )

    console.log({
    //   attestationData,
    //   domainSeparator,

      // encodedAttestation,
      encodedAttestationLength: encodedAttestation.length,
      encodedAttestationHexLength: encodedAttestation.substring(2).length,
      encodedAttestationByteLength: web3.utils.hexToBytes(encodedAttestation).length,
      expectedEncodedAttestationByteLength: '< ' + attestationByteSize,

      // signedAttestation,
      signedAttestationLength: signedAttestation.length,
      signedAttestationHexLength: signedAttestation.substring(2).length,
      signedAttestationByteLength: web3.utils.hexToBytes(signedAttestation).length,
      expectedSignedAttestationByteLength: '< ' + attestationByteSize,

      encodedAttestationPlusSignatureByteLength: (
        web3.utils.hexToBytes(encodedAttestation).length +
        web3.utils.hexToBytes(signedAttestation).length
      ),
      
      // subgraphIdHex0x,
      subgraphIdHex0xLength: subgraphIdHex0x.length,
      // subgraphIdHex,
      subgraphIdHexLength: subgraphIdHex.length,
      // subgraphIdBytes,
      subgraphIdByteLength: subgraphIdBytes.length,

      // tokensReceivedHexData,
      tokensReceivedHexDataLength: tokensReceivedHexData.length,
      tokensReceivedByteDataLength: data.length,
      expectedTokensReceivedByteDataLength: 33 + attestationByteSize,

      // dataSentToTokensReceived: String("[" + data.toString() + "]"),
      PASS: data.length === 33 + attestationByteSize, // data.length should be 1 + 32 + 197 = 230
      discrepancy: data.length - (33 + attestationByteSize)
    })
    return data
  }
})
