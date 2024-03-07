import { Consola } from 'consola'
import inquirer from 'inquirer'
import { utils } from 'ethers'

import '@nomiclabs/hardhat-ethers'

const { getAddress } = utils

export const askConfirm = async (message: string) => {
  const res = await inquirer.prompt({
    name: 'confirm',
    type: 'confirm',
    message,
  })
  return res.confirm ? res.confirm as boolean : false
}

export const promptContractAddress = async (name: string, logger: Consola): Promise<string | null> => {
  const res1 = await inquirer.prompt({
    name: 'contract',
    type: 'input',
    message: `What is the ${name} address?`,
  })

  try {
    return getAddress(res1.contract)
  } catch (err) {
    logger.error(err)
    return null
  }
}

export const getDeploymentName = async (defaultName: string): Promise<string> => {
  const res = await inquirer.prompt({
    name: 'deployment-name',
    type: 'input',
    default: defaultName,
    message: 'Save deployment as?',
  })
  return res['deployment-name'] as string
}
