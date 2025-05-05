import debug from 'debug'

const LOG_BASE = 'graph:deployments'
export const logDebug = debug(`${LOG_BASE}:debug`)
export const logInfo = debug(`${LOG_BASE}:info`)
export const logWarn = debug(`${LOG_BASE}:warn`)
export const logError = debug(`${LOG_BASE}:error`)

// if (process.env.DEBUG === undefined) {
//   debug.enable(`${LOG_BASE}:info`)
// }
