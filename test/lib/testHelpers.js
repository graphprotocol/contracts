// @todo Use a better method to parse event logs. This is limited
// @dev See possible replacment: https://github.com/rkalis/truffle-assertions
module.exports = {

    getParamFromTxEvent: (
        transaction,
        paramName,
        contractFactory,
        eventName
    ) => {
      assert.isObject(transaction)
      let logs = transaction.logs || transaction.events || []
      if(eventName != null) {
          logs = logs.filter((l) => l.event === eventName)
      }
      assert.equal(logs.length, 1, 'too many logs found!')
      let param = logs[0].args[paramName]
      if(contractFactory != null) {
          let contract = contractFactory.at(param)
          assert.isObject(contract, `getting ${paramName} failed for ${param}`)
          return contract
      } else return param
    }
    
}