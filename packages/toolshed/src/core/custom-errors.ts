import { getInterface } from '@graphprotocol/interfaces'
import { ErrorDescription } from 'ethers'

export function parseCustomError(error: string): string | null {
  const interfaces = [
    getInterface('HorizonStaking'),
    getInterface('SubgraphService'),
    getInterface('PaymentsEscrow'),
    getInterface('GraphTallyCollector'),
    getInterface('GraphPayments'),
  ]

  let decodedError: ErrorDescription | null = null
  for (const iface of interfaces) {
    decodedError = iface.parseError(error)
    if (decodedError) {
      break
    }
  }

  if (!decodedError) {
    return null
  }

  const argStrings = decodedError.fragment.inputs.map((input, i) => {
    const value = decodedError.args[i]
    return `${input.name}: ${value}`
  })

  return `${decodedError.name}(${argStrings.join(', ')})`
}
