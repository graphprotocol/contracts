/**
 * @dev Bonding Curve Formula explanation
 * @see https://yos.io/2018/11/10/bonding-curves/
 * 
 * Reserve Ratio Formula converted to graph function: `f(x) = mx^n`
 * or
 * y = m * x ^ n
 * y = (ReserveTokenBalance/(ReserveRatio * ContinuousShares^(1 / ReserveRatio))) 
 *    * x^((1/ReserveRatio) - 1)
 *
 * Fortunately, from the original formula two new formulas can be derived. One 
 * to calculate the amount of continuous tokens one receives for a given number 
 * of reserve tokens:
 *    PurchaseReturn = ContinuousShares * (
 *      (1 + ReserveTokensReceived / ReserveTokenBalance) ^ (ReserveRatio) 
 *      - 1
 *    )
 * And another to calculate the amount of reserve tokens one receives in exchange 
 * for a given number of continuous tokens:
 *    SaleReturn = ReserveTokenBalance * (
 *      1 - 
 *      (1 - ContinuousTokensReceived / ContinuousShares) ^ (1 / (ReserveRatio))
 *    )
 * These mirrored formulas are the final price functions we can use for our bonding 
 * curve contracts.
 *
 */

// contracts
const GraphToken = artifacts.require("./GraphToken.sol")
const Staking = artifacts.require("./Staking.sol")

// helpers
const GraphProtocol = require('../../graphProtocol.js')

/** 
 * testing constants
 */
const initialSupply = 10000,
  minimumCurationStakingAmount = 100,
  defaultReserveRatio = 500000, // PPM
  minimumIndexingStakingAmount = 100,
  maximumIndexers = 10,
  slashingPercent = 10,
  thawingPeriod = 60 * 60 * 24 * 7 // seconds
let deployedStaking,
  deployedGraphToken,
  gp

/* bonding curve params */
let totalShares, // total of staker's staked shares
  continuousShares, // total shares issued for subgraphId
  reserveTokenBalance, // total amount of tokens currently in reserves
  reserveRatios, // array of ratios used in bonding curve
  purchaseCount, // number of purchases to be made for each reserveRatios value
  purchaseAmount, // amount of tokens being staked (purchase amount)
  variancePercentage
const defaultParams = {
  totalShares: 1,
  continuousShares: 1, 
  reserveTokenBalance: minimumIndexingStakingAmount, 
  reserveRatios: [ // PPM
    1000000, // 100%
    900000, // 90%
    500000, // 50%
    100000, // 10%
  ],
  purchaseCount: 1,
  purchaseAmount: minimumCurationStakingAmount,
  variancePercentage: 0.001
}
function resetBondingParams() {
  totalShares = defaultParams.totalShares
  continuousShares = defaultParams.continuousShares,
  reserveTokenBalance = defaultParams.reserveTokenBalance,
  reserveRatios = defaultParams.reserveRatios
  purchaseCount = defaultParams.purchaseCount
  purchaseAmount = defaultParams.purchaseAmount
  variancePercentage = defaultParams.variancePercentage
}

contract('Staking (Bonding Curve)', ([
  deploymentAddress,
  daoContract,
  ...accounts
]) => {
  before(async () => {
    resetBondingParams()

    // deploy GraphToken contract
    deployedGraphToken = await GraphToken.new(
      daoContract, // governor
      initialSupply, // initial supply
      { from: deploymentAddress }
    )
    assert.isObject(deployedGraphToken, "Deploy GraphToken contract.")

    // deploy Staking contract
    deployedStaking = await Staking.new(
      daoContract, // <address> governor
      minimumCurationStakingAmount, // <uint256> minimumCurationStakingAmount
      defaultReserveRatio, // <uint256> defaultReserveRatio (ppm)
      minimumIndexingStakingAmount, // <uint256> minimumIndexingStakingAmount
      maximumIndexers, // <uint256> maximumIndexers
      slashingPercent, // <uint256> slashingPercent
      thawingPeriod, // <uint256> thawingPeriod
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

  describe('purchaseReturn formula', () => {
    it('...should calculate shares expected from `purchaseReturn` formula', async () => {

      // calculate expected shares using `purchseReturn` formula
      const expectedShares = await testBondingCurve(
        totalShares,
        continuousShares, 
        reserveTokenBalance, 
        purchaseCount,
        purchaseAmount
      )
      assert(typeof expectedShares === 'number', "Purchase Return is a number.")
    })

    // it('...should calculate shares expected from `stakeToShares`', async () => {
    //   const testingFactor = 10

    //   /**
    //    * stake X * `testingFactor` tokens in 1 transaction
    //    */
    //   // set vars
    //   resetBondingParams()
    //   purchaseAmount = minimumCurationStakingAmount*testingFactor
    //   // run test
    //   const oneTransaction = await testBondingCurve(
    //     totalShares,
    //     continuousShares, 
    //     reserveTokenBalance, 
    //     purchaseCount,
    //     purchaseAmount
    //   )

    //   /**
    //    * stake X tokens in `testingFactor` transactions
    //    */
    //   // set vars
    //   resetBondingParams()
    //   purchaseCount = testingFactor
    //   // run test
    //   const multipleTransactions = await testBondingCurve(
    //     totalShares,
    //     continuousShares, 
    //     reserveTokenBalance, 
    //     purchaseCount,
    //     purchaseAmount
    //   )

    //   console.log({ oneTransaction, multipleTransactions, pass: oneTransaction == multipleTransactions })
    //   // Assert totalShares ≈ totalSharesReceived (1X1000 ≈ (testingFactorx100 +/- variance))
    //   assert.closeTo(
    //     oneTransaction,
    //     multipleTransactions,
    //     ((oneTransaction + multipleTransactions) /2) * variancePercentage
    //   )
    // })

    // it('...should return expected amount of shares from `stakeToShares`', async () => {
    //   /**
    //    * @notice We are testing multiple staking transactions to test the variable parameters
    //    *  of the bonding curve as they influence the calculated results. (purchaseCount = 10)
    //    */

    //   // Reset / set bonding params
    //   resetBondingParams()
    //   purchaseCount = 2
    //   // Calculate expected value of shares
    //   const expectedShares = await testBondingCurve(
    //     totalShares,
    //     continuousShares, 
    //     reserveTokenBalance, 
    //     purchaseCount,
    //     purchaseAmount
    //   )
    //   assert(typeof expectedShares === 'number', "Purchase Return is a number.")

    //   // Reset / set bonding params
    //   resetBondingParams()
    //   purchaseCount = 2
    //   // Call contract for returned value of shares
    //   let stakeToShares = await iterateStakeToShares(
    //     totalShares,
    //     continuousShares, 
    //     reserveTokenBalance, 
    //     purchaseCount,
    //     purchaseAmount
    //   )
    //   assert(typeof stakeToShares === 'number', "Stake to Shares is a number.")
    //   assert.closeTo(
    //     stakeToShares,
    //     expectedShares,
    //     ((stakeToShares + expectedShares) /2) * variancePercentage
    //   )
    //   console.log({ stakeToShares, expectedShares, pass: stakeToShares == expectedShares })
    // }) 

    it('...should return number of shares from `stakeToShares`', async () => {
      // Reset / set bonding params
      resetBondingParams()
      // Call contract for returned number of shares
      let stakeToShares = await iterateStakeToShares(
        totalShares,
        continuousShares, 
        reserveTokenBalance, 
        purchaseCount,
        purchaseAmount
      )
      assert(typeof stakeToShares === 'number', "Stake to Shares is a number.")
    })

    it('...should return diminishing number shares from `stakeToShares` in 10 transactions', async () => {
      // Reset / set bonding params
      resetBondingParams()
      // Call contract for returned number of shares
      let stakeToShares = await iterateStakeToShares(
        totalShares,
        continuousShares, 
        reserveTokenBalance, 
        10,
        purchaseAmount,
        true // test diminishing return
      )
      assert(typeof stakeToShares === 'number', "Stake to Shares is a number.")
    })

    // it("...should print some purchaseFormula logging", () => {
    //   require('./bondingCurveFormula.js')
    // })
  })
})

/**
 * @dev Iterate through `reserveRatios` and `purchaseCount` to calculate expected staking increase
 * @param {uint256} _totalShares 
 * @param {uint256} _continuousShares 
 * @param {uint256} _reserveTokenBalance 
 * @param {uint256} _purchaseCount 
 * @param {uint256} _purchaseAmount 
 */
async function testBondingCurve(
  _totalShares,
  _continuousShares, 
  _reserveTokenBalance, 
  _purchaseCount,
  _purchaseAmount
) {
  let rtn = 0
  for (let r = 0; r < reserveRatios.length; r++) {
    // reset vars for this ratio
    totalShares = _totalShares
    continuousShares = _continuousShares
    reserveTokenBalance = _reserveTokenBalance
    // make purchases for this ratio
    for (let p = 0; p < _purchaseCount; p++) {
      const shares = await computeStakeToShares(_purchaseAmount, reserveRatios[r], purchaseReturn)
      rtn += shares
    }
  }
  return rtn
}

/**
 * @dev Iterate through `reserveRatios` and `purchaseCount` to increase stake
 * @param {uint256} _totalShares 
 * @param {uint256} _continuousShares 
 * @param {uint256} _reserveTokenBalance 
 * @param {uint256} _purchaseCount 
 * @param {uint256} _purchaseAmount 
 */
async function iterateStakeToShares(
  _totalShares,
  _continuousShares, 
  _reserveTokenBalance, 
  _purchaseCount,
  _purchaseAmount,
  _affirmTokenPriceIncrease
) {
  let rtn, lastReturn = 1
  for (let r = 0; r < reserveRatios.length; r++) {
    // reset vars for this ratio
    totalShares = _totalShares
    continuousShares = _continuousShares
    reserveTokenBalance = _reserveTokenBalance
    
    // make purchases for this ratio
    for (let p = 0; p < _purchaseCount; p++) {
      rtn = await computeStakeToShares(_purchaseAmount, reserveRatios[r])
      if (_affirmTokenPriceIncrease && rtn > lastReturn) {
        console.error(new Error(`Price of shares has behaved unexpectedly.`))
        return false
      }
    }
  }
  return rtn
}

/**
 * @dev Return the computed number of shares based on params
 * @param {uint256} _purchaseAmount // Amount of tokens being staked (purchase amount)
 * @param {uint256} _reserveRatio // Reserve ratio used in bonding curve
 * @param {function} _stakingMethod // method to use for calculation
 */
async function computeStakeToShares(_purchaseAmount, _reserveRatio, _stakingMethod ) {
  try {
    if (!_stakingMethod) _stakingMethod = gp.staking.stakeToShares
    let sharesReturned = 0
    const firstStake = !continuousShares
    if (firstStake) {
      continuousShares = 1
      reserveTokenBalance = minimumCurationStakingAmount
      _purchaseAmount -= minimumCurationStakingAmount
      sharesReturned = totalShares = 1
    }
    if (_purchaseAmount > 0) {
      const shares = parseInt(await _stakingMethod(
        _purchaseAmount, // Amount of tokens being staked (purchase amount)
        reserveTokenBalance, // Total amount of tokens currently in reserves
        continuousShares, // Total amount of current shares issued
        _reserveRatio // Reserve ratio
      ))
      // console.log(`Staking ${_purchaseAmount} tokens (against ${reserveTokenBalance} existing tokens) returns ${shares} shares (plus ${continuousShares} previous total shares) for ${shares + continuousShares} total issued shares. (using ${_stakingMethod === gp.staking.stakeToShares ? 'SOL' : 'JS'})`)
      continuousShares += shares
      reserveTokenBalance += _purchaseAmount
      totalShares += shares
      sharesReturned += shares
    }
    return sharesReturned
  }
  catch (err) { console.error(err) }
}

/**
 * @title Stake To Shares formula
 * @dev Calculate number of shares that should be issued in return for
 *      staking of _purchaseAmount of tokens, along the given bonding curve
 * @param {uint256} _reserveTokensReceived Amount of tokens being staked (purchase amount)
 * @param {uint256} _reserveTokenBalance Total amount of tokens currently in reserves
 * @param {uint256} _continuousShares Total amount of current shares issued
 * @param {uint256} _reserveRatio Desired reserve ratio to maintain (in PPM)
 */
function purchaseReturn(
  _reserveTokensReceived, 
  _reserveTokenBalance, 
  _continuousShares, 
  _reserveRatio
) {
  _reserveRatio = parseFloat(_reserveRatio)
  // convert PPM ratios
  if (_reserveRatio > 1) _reserveRatio = _reserveRatio / 1000000
  return _continuousShares * (
    (1 + _reserveTokensReceived / _reserveTokenBalance) ^ _reserveRatio 
    - 1
  )
}

/**
 * @title Shares To Stake formula
 * @param {uint256} _continuousShares 
 * @param {uint256} _continuousTokensReceived 
 * @param {uint256} _reserveTokenBalance 
 * @param {uint256} _reserveRatio 
 */
function saleReturn(
  _continuousShares, 
  _continuousTokensReceived, 
  _reserveTokenBalance, 
  _reserveRatio
) {
  // convert PPM ratios
  if (_reserveRatio > 1) _reserveRatio = _reserveRatio / 1000000
  return _reserveTokenBalance * (
    1 - 
    (1 - _continuousTokensReceived / _continuousShares) ^ (1 / (_reserveRatio))
  )
}