import debug from 'debug'

const LOG_BASE = 'hardhat:gre'

export const logDebug = debug(`${LOG_BASE}:debug`)
export const logWarn = debug(`${LOG_BASE}:warn`)
export const logError = debug(`${LOG_BASE}:error`)
