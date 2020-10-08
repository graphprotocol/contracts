#!/usr/bin/env ts-node
import * as dotenv from 'dotenv'
import yargs from 'yargs'

import { deployCommand } from './commands/deploy'
import { migrateCommand } from './commands/migrate'
import { proxyCommand } from './commands/proxy'
import { verifyCommand } from './commands/verify'
import { protocolCommand } from './commands/protocol'
import { contractsCommand } from './commands/contracts'
import { transferTeamTokensCommand } from './commands/transferTeamTokens'
import { simulationCommand } from './commands/simulations'
import { airdropCommand } from './commands/airdrop'

import { cliOpts } from './constants'

dotenv.config()

yargs
  .env(true)
  .option('a', cliOpts.addressBook)
  .option('m', cliOpts.mnemonic)
  .option('p', cliOpts.providerUrl)
  .option('n', cliOpts.accountNumber)
  .command(deployCommand)
  .command(migrateCommand)
  .command(proxyCommand)
  .command(verifyCommand)
  .command(protocolCommand)
  .command(contractsCommand)
  .command(transferTeamTokensCommand)
  .command(simulationCommand)
  .command(airdropCommand)
  .demandCommand(1, 'Choose a command from the above list')
  .help().argv
