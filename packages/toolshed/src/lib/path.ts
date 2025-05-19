import fs from 'fs'
import path from 'path'

export function findPathUp(startPath: string, pathToFind: string): string | null {
  let currentDir = path.resolve(startPath)

  while (currentDir !== path.dirname(currentDir)) {
    const candidate = path.join(currentDir, pathToFind)
    if (fs.existsSync(candidate) && fs.statSync(candidate).isDirectory()) {
      return candidate
    }

    const parentDir = path.dirname(currentDir)
    if (parentDir === currentDir) {
      return null
    }

    currentDir = parentDir
  }

  return null
}

// Useful if you need to resolve a path to a file that might not exist but you
// know it will eventually exist in the node_modules directory
export function resolveNodeModulesPath(fileName: string): string {
  const basePath = findPathUp(__dirname, 'node_modules')
  if (!basePath) {
    throw new Error('Could not find node_modules directory')
  }
  return path.resolve(basePath, fileName)
}

// Useful if you need to resolve a path to a file that exists in a package
export function resolvePackagePath(packageName: string, relativePath: string): string {
  const packageRoot = path.dirname(require.resolve(`${packageName}/package.json`))
  return path.join(packageRoot, relativePath)
}
