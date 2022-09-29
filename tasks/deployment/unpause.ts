import { graphTask } from '../../gre/gre'

graphTask('migrate:unpause', 'Unpause protocol').setAction(async (taskArgs, hre) => {
  const { contracts, getNamedAccounts } = hre.graph(taskArgs)
  const { governor } = await getNamedAccounts()

  console.log('> Unpausing protocol')
  const tx = await contracts.Controller.connect(governor).setPaused(false)
  await tx.wait()
  console.log('Done!')
})
