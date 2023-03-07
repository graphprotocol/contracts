import hre from 'hardhat'
import '@nomiclabs/hardhat-ethers'

import { TestLFM } from '../build/types/TestLFM'
import { TestPRB } from '../build/types/TestPRB'
import { BigNumber } from 'ethers'

interface FormulaResult {
  result: BigNumber
  gasUsed?: BigNumber
}

interface ExpResult {
  value: BigNumber
  result: BigNumber
  gasUsed?: BigNumber
}

const MIN_TX_GAS = BigNumber.from(21000)

async function main() {
  // Deploy TestLFM contract
  const TestLFMFactory = await hre.ethers.getContractFactory('TestLFM')
  const testLFM = (await TestLFMFactory.deploy()) as TestLFM
  await testLFM.deployed()
  console.log(`TestLFM deployed to ${testLFM.address}`)

  // Deploy TestPRB contract
  const TestPRBFactory = await hre.ethers.getContractFactory('TestPRB')
  const testPRB = (await TestPRBFactory.deploy()) as TestPRB
  await testPRB.deployed()
  console.log(`TestPRB deployed to ${testPRB.address}`)

  console.log(`\n*** Exponential Test ***`)
  console.log('Calculates rebates with the following formula:')
  console.log('(1 - exp(-(LAMBDA_NUMERATOR / LAMBDA_DENOMINATOR) * (STAKE / FEES))) * FEES)')
  console.log('Calculates exponentiation with the following formula:')
  console.log('exp(-value) * 1e18')

  // *** INPUT VALUES ***
  const FEES = 10e18
  const STAKE = 100e18
  const LAMBDA_NUMERATOR = 2
  const LAMBDA_DENOMINATOR = 10
  const expValues = [0, 1, 5, 10, 20, 40, 45, 60]

  // *** JavaScript ***
  console.log(`\nCalculating formula and exp values using javascript...`)
  const jsExpResults: ExpResult[] = []
  const jsFormulaResult: FormulaResult = {
    result: BigNumber.from(
      ((1 - Math.exp(-(LAMBDA_NUMERATOR / LAMBDA_DENOMINATOR) * (STAKE / FEES))) * FEES).toString(),
    ),
  }

  for (const value of expValues) {
    jsExpResults.push({
      value: BigNumber.from(value),
      result: BigNumber.from(Math.round(Math.exp(-value) * 1e18).toString()),
    })
  }

  // *** LibFixedMath: Formula ***
  console.log(`\nCalculate formula using solidity LibFixedMath...`)
  const solExpLFMResults: ExpResult[] = []

  const tx = await testLFM.LFMCalcTx()
  const receipt = await tx.wait()
  const solLFMFormulaResult: FormulaResult = {
    gasUsed: receipt.gasUsed.sub(MIN_TX_GAS),
    result: await testLFM.LFMCalc(),
  }

  // *** LibFixedMath: Exp ***
  console.log(`\nCalculate exp using solidity LibFixedMath...`)

  for (const value of expValues) {
    const expTx = await testLFM.LFMExpTx(value)
    const expReceipt = await expTx.wait()
    const expResult = await testLFM.LFMExpMul(value)
    solExpLFMResults.push({
      value: BigNumber.from(value),
      result: expResult,
      gasUsed: expReceipt.gasUsed.sub(MIN_TX_GAS),
    })
  }

  // *** PRB.Math: Formula ***
  console.log(`\nCalculate formula using solidity PRB.Math...`)
  const solExpPRBResults: ExpResult[] = []

  const txPRB = await testPRB.PRBCalcTx()
  const receiptPRB = await txPRB.wait()
  const solPRBFormulaResult: FormulaResult = {
    gasUsed: receiptPRB.gasUsed.sub(MIN_TX_GAS),
    result: await testPRB.PRBCalc(),
  }

  // *** PRB: Exp ***
  console.log(`\nCalculate exp using solidity PRB.Math...`)

  for (const value of expValues) {
    const expTx = await testPRB.PRBExpTx(-value)
    const expReceipt = await expTx.wait()
    const expResult = await testPRB.PRBExpMul(-value)
    solExpPRBResults.push({
      value: BigNumber.from(value),
      result: expResult,
      gasUsed: expReceipt.gasUsed.sub(MIN_TX_GAS),
    })
  }

  // Compare
  console.log(`\n*** Compare formula precision...`)
  console.log(`JavaScript   =`, jsFormulaResult.result.toString())
  console.log(`LibFixedMath =`, solLFMFormulaResult.result.toString())
  console.log(`PRB.Math     =`, solPRBFormulaResult.result.toString())

  // log error
  const error = jsFormulaResult.result.sub(solLFMFormulaResult.result).abs()
  console.log(`LibFixedMath Error =`, error.toString())
  const prbError = jsFormulaResult.result.sub(solPRBFormulaResult.result).abs()
  console.log(`PRB.Math Error     =`, prbError.toString())

  console.log(`LibFixedMath gas used =`, solLFMFormulaResult.gasUsed.toString())
  console.log(`PRB.Math gas used     =`, solPRBFormulaResult.gasUsed.toString())

  console.log(`\n*** Compare exp precision...`)
  for (let index = 0; index < expValues.length; index++) {
    const value = expValues[index]
    console.log(`\nCompare exp(-${value})*1e18 values...`)

    console.log(`JavaScript   =`, jsExpResults[index].result.toString())
    console.log(`LibFixedMath =`, solExpLFMResults[index].result.toString())
    console.log(`PRB.Math     =`, solExpPRBResults[index].result.toString())

    const error = jsExpResults[index].result.sub(solExpLFMResults[index].result).abs()
    console.log(`LibFixedMath Error =`, error.toString())
    const prbError = jsExpResults[index].result.sub(solExpPRBResults[index].result).abs()
    console.log(`PRB.Math Error     =`, prbError.toString())

    console.log(`LibFixedMath gas used =`, solExpLFMResults[index].gasUsed.toString())
    console.log(`PRB.Math gas used     =`, solExpPRBResults[index].gasUsed.toString())
  }
}

main()
  .then(() => {
    process.exit(0)
  })
  .catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
