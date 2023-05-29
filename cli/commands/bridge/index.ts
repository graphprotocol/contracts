import yargs, { Argv } from 'yargs'

import { redeemSendToL2Command, sendToL2Command } from './to-l2'
import { startSendToL1Command, finishSendToL1Command, waitFinishSendToL1Command } from './to-l1'
import { cliOpts } from '../../defaults'
import {
  finishSubgraphTransferToL2Command,
  sendCurationToL2Command,
  sendSubgraphToL2Command,
} from './gns-transfer-tools'
import { sendDelegationToL2Command, sendStakeToL2Command } from './staking-transfer-tools'

export const bridgeCommand = {
  command: 'bridge',
  describe: 'Graph token bridge actions.',
  builder: (yargs: Argv): yargs.Argv => {
    return yargs
      .option('-l', cliOpts.l2ProviderUrl)
      .command(sendToL2Command)
      .command(redeemSendToL2Command)
      .command(startSendToL1Command)
      .command(finishSendToL1Command)
      .command(waitFinishSendToL1Command)
      .command(sendSubgraphToL2Command)
      .command(finishSubgraphTransferToL2Command)
      .command(sendCurationToL2Command)
      .command(sendStakeToL2Command)
      .command(sendDelegationToL2Command)
  },
  handler: (): void => {
    yargs.showHelp()
  },
}
