import { ArgumentType, Artifact, ContractOptions, IgnitionModuleBuilder } from '@nomicfoundation/ignition-core'

export type ImplementationMetadata = {
  name: string
  artifact?: Artifact
  constructorArgs?: ArgumentType[]
  initArgs?: ArgumentType[]
}

export function deployImplementation(
  m: IgnitionModuleBuilder,
  contract: ImplementationMetadata,
  options?: ContractOptions,
) {
  let implementation
  if (contract.artifact === undefined) {
    implementation = m.contract(contract.name, contract.constructorArgs, options)
  } else {
    implementation = m.contract(contract.name, contract.artifact, contract.constructorArgs, options)
  }
  return implementation
}
