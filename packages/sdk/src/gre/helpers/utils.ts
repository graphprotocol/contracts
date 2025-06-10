import path from 'path'

export function normalizePath(_path: string, graphPath?: string): string {
  if (!path.isAbsolute(_path) && graphPath !== undefined) {
    _path = path.join(graphPath, _path)
  }
  return _path
}
