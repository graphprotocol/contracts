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

let a = 100 // payment amount
let s = 1 // total shares
let t = 100 // total tokens
let r = 0.5 // ratio
let p, n

p = [s, a, t, r]
n = purchaseReturn(...p) // calc shares
s += n // increase total shares
t += a // increase total tokens
a = a*2 // increase purchase amount
console.log(p, n, s)

p = [s, a, t, r]
n = purchaseReturn(...p) // calc shares
s += n // increase total shares
t += a // increase total tokens
a = a*2 // increase purchase amount
console.log(p, n, s)

p = [s, a, t, r]
n = purchaseReturn(...p) // calc shares
s += n // increase total shares
t += a // increase total tokens
a = a*2 // increase purchase amount
console.log(p, n, s)


