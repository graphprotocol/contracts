import path from 'path'

/**
 * Resolves the absolute path to an address book file relative to an existing file.
 *
 * This function uses `require.resolve` (from the caller's context) on the provided
 * `existingAddressBookPath` to locate a known file (e.g., an existing address book JSON file).
 * Once located, it returns the absolute path to the desired `addressBookPath`, which is resolved
 * relative to the directory of the existing file.
 *
 * If the existing file cannot be resolved, the function returns `undefined`.
 *
 * This is useful when:
 * - You know the location of one file in a package or module.
 * - You need the path to another file in the same directory (or nearby), whether or not it exists.
 *
 * ## Examples
 *
 * ```ts
 * // Example 1: Resolve a different file in the same folder
 * // Locates: <node_modules>/@graphprotocol/horizon/addresses.json
 * // Returns: <node_modules>/@graphprotocol/horizon/addresses-hardhat.json
 * resolveAddressBook(require, 'addresses.json', 'addresses-hardhat.json')
 * ```
 *
 * ```ts
 * // Example 2: Resolve the same file you use for lookup
 * // Locates and returns: <node_modules>/@graphprotocol/address-book/horizon/addresses.json
 * resolveAddressBook(require, '@graphprotocol/address-book/horizon/addresses.json')
 * ```
 *
 * @param callerRequire - The `require` function from the calling module, used for resolution relative to the caller.
 * @param existingAddressBookPath - A resolvable path to an existing file (relative to the caller), used as an anchor. Defaults to `"addresses.json"`.
 * @param addressBookPath - The path (relative to the anchor's directory) to the file you want returned. Defaults to `"addresses.json"`.
 * @returns The absolute path to the requested file, or `undefined` if the existing file cannot be resolved.
 */
export function resolveAddressBook(
  callerRequire: typeof require,
  existingAddressBookPath: string = 'addresses.json',
  addressBookPath: string = 'addresses.json',
): string | undefined {
  try {
    const packageRoot = path.dirname(callerRequire.resolve(`${existingAddressBookPath}`))
    return path.join(packageRoot, addressBookPath)
  } catch (_) {
    return undefined
  }
}
