#!/usr/bin/env python3
"""
Repository Comparison Script

Compares contract artifacts between two repository directories to detect functional differences.
This is useful for verifying that dependency upgrades or other changes don't affect contract bytecode.

Usage: ./scripts/compare-repos.py <repo1_path> <repo2_path>
Example: ./scripts/compare-repos.py /path/to/repo-v3.4.1 /path/to/repo-v3.4.2

The script will:
1. Auto-discover all artifact directories in both repositories
2. Find matching contracts between the repositories
3. Compare bytecode while stripping metadata hashes
4. Report functional differences
"""

import os
import sys
import json
import re
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Set


def strip_metadata(bytecode: str) -> str:
    """
    Strip Solidity metadata hash from bytecode to focus on functional differences.
    
    Metadata hash pattern: a264697066735822<32-byte-hash>64736f6c63<version>
    Where: a264697066735822 = "ipfs" in hex, 64736f6c63 = "solc" in hex
    """
    if bytecode.startswith('0x'):
        bytecode = bytecode[2:]
    
    # Remove metadata hash pattern
    return re.sub(r'a264697066735822.*', '', bytecode)


def get_contract_bytecode(artifact_file: Path) -> Optional[str]:
    """Extract and process bytecode from contract artifact JSON file."""
    try:
        with open(artifact_file, 'r') as f:
            artifact = json.load(f)
        
        bytecode = artifact.get('bytecode', '')
        if not bytecode or bytecode == '0x':
            return None
            
        return strip_metadata(bytecode)
    except (json.JSONDecodeError, FileNotFoundError, KeyError):
        return None


def find_artifact_directories(repo_path: Path) -> List[Tuple[str, Path]]:
    """
    Find all artifact directories in a repository.
    Returns list of (package_name, artifact_path) tuples.
    """
    artifact_dirs = []
    
    # Standard artifact patterns
    patterns = [
        "packages/*/artifacts",
        "packages/*/build/artifacts", 
        "packages/*/build/contracts"
    ]
    
    for pattern in patterns:
        for artifact_dir in repo_path.glob(pattern):
            if artifact_dir.is_dir():
                # Extract package name from path
                parts = artifact_dir.relative_to(repo_path).parts
                if len(parts) >= 2 and parts[0] == "packages":
                    package_name = parts[1]
                    artifact_dirs.append((package_name, artifact_dir))
    
    return artifact_dirs


def find_contract_artifacts(artifact_dir: Path) -> Dict[str, Path]:
    """
    Find all contract artifact JSON files in an artifact directory.
    Returns dict mapping relative_path -> absolute_path.
    """
    contracts = {}
    
    for json_file in artifact_dir.rglob("*.json"):
        # Skip debug files and interface files
        if json_file.name.endswith('.dbg.json'):
            continue
        if json_file.name.startswith('I') and not json_file.name.startswith('IL'):
            continue
            
        # Get relative path from artifact directory
        rel_path = json_file.relative_to(artifact_dir)
        contracts[str(rel_path)] = json_file
    
    return contracts


def compare_repositories(repo1_path: Path, repo2_path: Path) -> None:
    """Compare contract artifacts between two repositories."""
    
    print(f"🔍 Comparing repositories:")
    print(f"   Repo 1: {repo1_path}")
    print(f"   Repo 2: {repo2_path}")
    print(f"   Excluding metadata hashes to focus on functional differences\n")
    
    # Find artifact directories in both repos
    repo1_artifacts = find_artifact_directories(repo1_path)
    repo2_artifacts = find_artifact_directories(repo2_path)
    
    # Group by package name
    repo1_packages = {pkg: path for pkg, path in repo1_artifacts}
    repo2_packages = {pkg: path for pkg, path in repo2_artifacts}
    
    # Find common packages
    common_packages = set(repo1_packages.keys()) & set(repo2_packages.keys())
    
    if not common_packages:
        print("❌ No common packages found between repositories!")
        return
    
    total_compared = 0
    total_identical = 0
    total_different = 0
    total_no_bytecode = 0
    
    identical_contracts = []
    different_contracts = []
    
    for package in sorted(common_packages):
        print(f"🔍 Comparing {package}...")
        print(f"   Repo 1: {repo1_packages[package]}")
        print(f"   Repo 2: {repo2_packages[package]}")
        
        # Find contracts in both packages
        repo1_contracts = find_contract_artifacts(repo1_packages[package])
        repo2_contracts = find_contract_artifacts(repo2_packages[package])
        
        # Find common contracts
        common_contracts = set(repo1_contracts.keys()) & set(repo2_contracts.keys())
        
        if not common_contracts:
            print(f"   ❌ No common contracts found!\n")
            continue
            
        print(f"   📊 Found {len(common_contracts)} common contracts")
        
        package_identical = 0
        package_different = 0
        package_no_bytecode = 0
        
        for contract_path in sorted(common_contracts):
            # Get bytecode from both versions
            bytecode1 = get_contract_bytecode(repo1_contracts[contract_path])
            bytecode2 = get_contract_bytecode(repo2_contracts[contract_path])
            
            # Extract contract name for display
            contract_name = Path(contract_path).stem
            
            if bytecode1 is None and bytecode2 is None:
                print(f"   ⚪ {contract_path}")
                package_no_bytecode += 1
                total_no_bytecode += 1
            elif bytecode1 == bytecode2:
                print(f"   ✅ {contract_path}")
                identical_contracts.append(f"{package}/{contract_path} ({contract_name})")
                package_identical += 1
                total_identical += 1
            else:
                print(f"   🧨 {contract_path}")
                different_contracts.append(f"{package}/{contract_path} ({contract_name})")
                package_different += 1
                total_different += 1
            
            total_compared += 1
        
        print(f"   📊 Package summary: {package_identical} identical, {package_different} different, {package_no_bytecode} no bytecode\n")
    
    # Overall summary
    print("📋 OVERALL SUMMARY:\n")
    
    if identical_contracts:
        print(f"✅ FUNCTIONALLY IDENTICAL ({len(identical_contracts)} contracts):")
        for contract in identical_contracts:
            print(f"  - {contract}")
        print()
    
    if different_contracts:
        print(f"🧨 FUNCTIONAL DIFFERENCES ({len(different_contracts)} contracts):")
        for contract in different_contracts:
            print(f"  - {contract}")
        print()
    else:
        print("🧨 FUNCTIONAL DIFFERENCES (0 contracts):")
        print("  (none)\n")
    
    print(f"📊 Final Summary:")
    print(f"   Packages compared: {len(common_packages)}")
    print(f"   Total contracts compared: {total_compared}")
    print(f"   No bytecode (interfaces/abstract): {total_no_bytecode}")
    print(f"   Functionally identical: {total_identical}")
    print(f"   Functional differences: {total_different}")
    
    if total_different == 0:
        print(f"\n🎉 SUCCESS: All contracts are functionally identical!")
        print(f"   Any differences were only in metadata hashes.")
    else:
        print(f"\n⚠️  WARNING: {total_different} contracts have functional differences!")
        print(f"   Review the differences above before proceeding.")


def main():
    if len(sys.argv) != 3:
        print("Usage: ./scripts/compare-repos.py <repo1_path> <repo2_path>")
        print("Example: ./scripts/compare-repos.py /path/to/repo-v3.4.1 /path/to/repo-v3.4.2")
        sys.exit(1)
    
    repo1_path = Path(sys.argv[1]).resolve()
    repo2_path = Path(sys.argv[2]).resolve()
    
    if not repo1_path.exists():
        print(f"❌ Repository 1 does not exist: {repo1_path}")
        sys.exit(1)
    
    if not repo2_path.exists():
        print(f"❌ Repository 2 does not exist: {repo2_path}")
        sys.exit(1)
    
    if repo1_path == repo2_path:
        print(f"❌ Both repository paths are the same: {repo1_path}")
        sys.exit(1)
    
    compare_repositories(repo1_path, repo2_path)


if __name__ == "__main__":
    main()
