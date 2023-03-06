import hre from 'hardhat'
import '@nomiclabs/hardhat-ethers'

import { TestExponential } from '../build/types/TestExponential'
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

async function main() {
  // Deploy TestExponential contract
  const TestExponentialFactory = await hre.ethers.getContractFactory('TestExponential')
  const testExponential = (await TestExponentialFactory.deploy()) as TestExponential
  await testExponential.deployed()
  console.log(`TestExponential deployed to ${testExponential.address}`)

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
  const expValues = [0, 1, 5, 10, 20, 40, 60]

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

  const tx = await testExponential.LFMCalcTx()
  const receipt = await tx.wait()
  const solLFMFormulaResult: FormulaResult = {
    gasUsed: receipt.gasUsed,
    result: await testExponential.LFMCalc(),
  }

  // *** LibFixedMath: Exp ***
  console.log(`\nCalculate exp using solidity LibFixedMath...`)

  for (const value of expValues) {
    const expTx = await testExponential.LFMExpTx(value)
    const expReceipt = await expTx.wait()
    const expResult = await testExponential.LFMExpMul(value)
    solExpLFMResults.push({
      value: BigNumber.from(value),
      result: expResult,
      gasUsed: expReceipt.gasUsed,
    })
  }

  // Compare
  console.log(`\n*** Compare implementation precision...`)

  console.log(jsFormulaResult)
  console.log(solLFMFormulaResult)
  console.log(solExpLFMResults)

  console.log(`\n*** Compare exp precision...`)
  for (let index = 0; index < expValues.length; index++) {
    const value = expValues[index]
    console.log(`\nCompare exp(-${value})*1e18 values...`)
    console.log(`JavaScript   =`, jsExpResults[index].result.toString())
    console.log(`LibFixedMath =`, solExpLFMResults[index].result.toString())
    const error = jsExpResults[index].result.sub(solExpLFMResults[index].result).abs()
    console.log(`LibFixedMath Error =`, error.toString())
    console.log(`LibFixedMath gas used =`, solExpLFMResults[index].gasUsed.toString())
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
