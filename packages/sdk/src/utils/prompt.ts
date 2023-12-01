import inquirer from 'inquirer'

export const confirm = async (message: string, skip: boolean): Promise<boolean> => {
  if (skip) return true
  const res = await inquirer.prompt({
    name: 'confirm',
    type: 'confirm',
    message,
  })
  if (!res.confirm) {
    console.info('Cancelled')
    return false
  }
  return true
}
