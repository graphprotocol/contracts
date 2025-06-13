import path from 'path'

/**
 * Use to get a resolved path to an address book file wether it exists or not
 * If addresses.json does not exist in the package root, returns undefined
 * @param callerRequire - The require function to use
 * @param packageName - The name of the package to resolve the address book for
 * @param addressBook - The name of the address book file to resolve
 * @returns The resolved path to the address book file
 */
export function resolveAddressBook(
  callerRequire: typeof require,
  packageName: string,
  addressBook?: string,
): string | undefined {
  try {
    const packageRoot = path.dirname(callerRequire.resolve(`${packageName}/addresses.json`))
    return path.join(packageRoot, addressBook ?? 'addresses.json')
  } catch (_) {
    return undefined
  }
}
