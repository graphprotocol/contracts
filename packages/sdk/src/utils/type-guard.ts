// https://stackoverflow.com/questions/58278652/generic-enum-type-guard
export function isSomeEnum<T extends Record<string, unknown>>(
  e: T,
): (token: unknown) => token is T[keyof T] {
  const keys = Object.keys(e).filter((k) => {
    return !/^\d/.test(k)
  })
  const values = keys.map((k) => {
    return (e as any)[k]
  })
  return (token: unknown): token is T[keyof T] => {
    return values.includes(token)
  }
}
