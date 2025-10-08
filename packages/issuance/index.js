// Main entry point for @graphprotocol/issuance
// This package provides issuance contracts and artifacts

const path = require('path')

module.exports = {
  contractsDir: path.join(__dirname, 'contracts'),
  artifactsDir: path.join(__dirname, 'artifacts'),
  typesDir: path.join(__dirname, 'types'),
  cacheDir: path.join(__dirname, 'cache'),
}
