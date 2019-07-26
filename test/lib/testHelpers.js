module.exports = {

  randomSubgraphIdHex: () => web3.utils.randomHex(32).substring(2),
  randomSubgraphIdBytes: (hex = web3.utils.randomHex(32)) => web3.utils.hexToBytes(hex),
  zerobytes: () => web3.utils.hexToBytes('0x0000000000000000000000000000000000000000000000000000000000000000'),
  zeroHex: () => '0x0000000000000000000000000000000000000000000000000000000000000000',
  zeroAddress: () => '0x0000000000000000000000000000000000000000',

  // deprecated
  getParamFromTxEvent: (
    transaction,
    paramName,
    contractFactory,
    eventName
  ) => {
    assert.isObject(transaction)
    let logs = transaction.logs || transaction.events || []
    if (eventName != null) {
      logs = logs.filter((l) => l.event === eventName)
    }
    assert.equal(logs.length, 1, 'too many logs found!')
    let param = logs[0].args[paramName]
    if (contractFactory != null) {
      let contract = contractFactory.at(param)
      assert.isObject(contract, `getting ${paramName} failed for ${param}`)
      return contract
    } else return param
  }

}