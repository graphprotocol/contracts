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
  _reserveRatio,
) {
  _reserveRatio = parseFloat(_reserveRatio)
  // convert PPM ratios
  if (_reserveRatio > 1) _reserveRatio = _reserveRatio / 1000000
  return (
    _continuousShares *
    ((1 + _reserveTokensReceived / _reserveTokenBalance) ^ (_reserveRatio - 1))
  )
}

const _defaults = {
  a: 100, // payment amount
  t: 100, // total tokens (from the first share)
  s: 1, // total shares (start with 1 so we bypass first share scenario)
  r: 1000000, // ratio (in PPM)
}

let a, t, s, r // variables can be reset to _default values with `resetVars`
let p // reusable/updatable array of `purchaseReturn` parameters as properties
let n // shares returned from `purchaseReturn` function

const resetVars = () => {
  a = _defaults.a
  t = a
  s = _defaults.s
  r = _defaults.r
  p = null
  n = null
}

const log = () => {
  console.log(
    `Staking ${p[0]} tokens (against ${
      p[1]
    } existing tokens) returns ${n} shares (plus ${
      p[2]
    } previous total shares) for ${n + p[2]} total issued shares.`,
  )
}

const purchaseShares = (iterations = 1) => {
  for (let i = 0; i < iterations; i++) {
    p = [a, t, s, r]
    n = purchaseReturn(...p) // calc shares
    s += n // increase total shares
    t += a // increase total tokens
    log()
  }
}

/** runs some tests and log some staking... */

resetVars()
console.log(
  `First share purchased for ${a} tokens at ${parseInt(
    (r / 1000000) * 100,
  )}% ratio`,
)

a = a * 10
console.log(`\nTEST${s}: spend 10x "amount" in one purchase...`)
purchaseShares()
const onePurchase = s
console.log(`RESULT: ${s} total shares received.`)

resetVars()
console.log(`\nTEST${s}: spend "amount" in 10x purchases...`)
purchaseShares(10)
const tenPurchases = s
console.log(`RESULT: ${s} total shares received.`)

console.log(
  `\n----\nRESULTS MATCH: ${onePurchase} === ${tenPurchases} : ${onePurchase ===
    tenPurchases}`,
)
