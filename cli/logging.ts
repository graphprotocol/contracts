import winston, { format } from 'winston'

// const fullFormatter = format.combine(
//   format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss.SSS' }),
//   format.colorize(),
//   format.printf(
//     ({ level, message, label, timestamp }) => `${timestamp} ${label || '-'} ${level}: ${message}`,
//   ),
// )

export const logger: winston.Logger = winston.createLogger({
  level: 'info',
  format: format.combine(
    format.colorize(),
    format.printf(({ message }) => `${message}`),
  ),
  transports: [new winston.transports.Console({ level: 'info' })],
})
