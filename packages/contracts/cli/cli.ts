#!/usr/bin/env ts-node
import * as dotenv from 'dotenv'
import yargs from 'yargs'

import { deployCommand } from './commands/deploy'
import { migrateCommand } from './commands/migrate'
import { proxyCommand } from './commands/proxy'
import { protocolCommand } from './commands/protocol'
import { contractsCommand } from './commands/contracts'
import { airdropCommand } from './commands/airdrop'
import { bridgeCommand } from './commands/bridge'

import { cliOpts } from './defaults'

dotenv.config()

yargs
  .parserConfiguration({
    'short-option-groups': true,
    'camel-case-expansion': true,
    'dot-notation': true,
    'parse-numbers': false,
    'parse-positional-numbers': false,
    'boolean-negation': true,
  })
  .env(true)
  .option('a', cliOpts.addressBook)
  .option('m', cliOpts.mnemonic)
  .option('p', cliOpts.providerUrl)
  .option('n', cliOpts.accountNumber)
  .option('s', cliOpts.skipConfirmation)
  .option('r', cliOpts.arbitrumAddressBook)
  .command(deployCommand)
  .command(migrateCommand)
  .command(proxyCommand)
  .command(protocolCommand)
  .command(contractsCommand)
  .command(airdropCommand)
  .command(bridgeCommand)
  .demandCommand(1, 'Choose a command from the above list')
  .help().argv
