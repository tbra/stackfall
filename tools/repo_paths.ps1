# Machine-independent default locations for the PowerShell tools (mirror of tools/repo_paths.py).
# Dot-source it: . (Join-Path $PSScriptRoot "repo_paths.ps1")
# The main checkout is <parent>/<name>; worktrees live in <parent>/<name>-worktrees and shared
# tooling state in <parent>/<name>-tools. Overrides: STACKFALL_WORKTREES, STACKFALL_TOOLS_ROOT.
function Get-StackfallMainRepo {
	$here = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
	$parent = Split-Path -Parent $here
	$parentName = Split-Path -Leaf $parent
	if ($parentName.EndsWith("-worktrees") -and $parentName.Length -gt "-worktrees".Length) {
		return (Join-Path (Split-Path -Parent $parent) $parentName.Substring(0, $parentName.Length - "-worktrees".Length))
	}
	return $here
}
function Get-StackfallToolsRoot {
	if ($env:STACKFALL_TOOLS_ROOT) { return $env:STACKFALL_TOOLS_ROOT }
	$main = Get-StackfallMainRepo
	return (Join-Path (Split-Path -Parent $main) ((Split-Path -Leaf $main) + "-tools"))
}
function Get-StackfallWorktreesRoot {
	if ($env:STACKFALL_WORKTREES) { return $env:STACKFALL_WORKTREES }
	$main = Get-StackfallMainRepo
	return (Join-Path (Split-Path -Parent $main) ((Split-Path -Leaf $main) + "-worktrees"))
}
