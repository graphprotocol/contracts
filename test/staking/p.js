/**
 * @dev Calculate number of shares that should be issued in return for
 *      staking of _purchaseAmount of tokens, along the given bonding curve
 * @param _reserveTokensReceived <uint256> - Amount of tokens being staked (purchase amount)
 * @param _reserveTokenBalance <uint256> - Total amount of tokens currently in reserves
 * @param _continuousShares <uint256> - Total amount of current shares issued
 * @param _reserveRatio <uint256> - Desired reserve ratio to maintain (in PPM)
 * @return issuedShares <uint256> - Amount of additional shares issued given the above
 */
function purchaseReturn(
  _continuousShares, 
  _reserveTokensReceived, 
  _reserveTokenBalance, 
  _reserveRatio
) {
  if (_reserveRatio > 1) _reserveRatio = _reserveRatio / 1000000
  return _continuousShares * (
    (1 + _reserveTokensReceived / _reserveTokenBalance) ^ (_reserveRatio) 
    - 1
  )
}

const _defaults = {
  a: 100, // payment amount
  s: 1, // total shares (start with 1 so we bypass first share scenario)
  t: 100, // total tokens (from the first share)
  r: 1000000, // ratio (in PPM)
}

let a, s, t, r // variables can be reset to _default values with `resetVars`
let p // reusable/updatable array of `purchaseReturn` parameters as properties
let n // shares returned from `purchaseReturn` function

const resetVars = () => {
  a = _defaults.a
  s = _defaults.s
  t = a
  r = _defaults.r
  p = null
  n = null
}

const log = () => {
  console.log(`Staking ${p[1]} tokens (against ${p[2]} existing tokens) returns ${n} shares (plus ${p[0]} previous total shares) for ${n + p[0]} total issued shares.`)
}

const purchaseShares = (iterations = 1) => {
  for(let i = 0; i < iterations; i++ ) {
    p = [s, a, t, r]
    n = purchaseReturn(...p) // calc shares
    s += n // increase total shares
    t += a // increase total tokens
    log()
  }
}


/** runs some tests and log some staking... */

resetVars()
console.log(`First share purchased for ${a} tokens at ${parseInt((r/1000000) * 100)}% ratio`)

a = a *10
console.log(`\nTEST${s}: spend 10x "amount" in one purchase...`)
purchaseShares()
const onePurchase = s
console.log(`RESULT: ${s} total shares received.`)

resetVars()
console.log(`\nTEST${s}: spend "amount" in 10x purchases...`)
purchaseShares(10)
const tenPurchases = s
console.log(`RESULT: ${s} total shares received.`)

console.log(`\n----\nRESULTS MATCH: ${onePurchase} === ${tenPurchases} : ${(onePurchase === tenPurchases)}`)
