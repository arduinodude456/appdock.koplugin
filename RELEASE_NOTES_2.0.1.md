# AppDock 2.0.1

## Storage

The Storage settings category now performs a real filesystem scan when the Settings DApp is rebuilt. It no longer reports 0 B merely because one storage directory is missing or an LFS call returns no iterator.

The scan uses protected LuaFileSystem calls, ignores `.` and `..`, limits recursion depth and file count for E-Ink responsiveness, and shows a safe fallback if a directory cannot be read.

Installed Store DApps are measured individually from their recorded installation files. The list is sorted by actual byte usage and shows the largest entries first with proportional E-Ink-friendly bars. This measures the installed DApp Lua files themselves; personal files created by a DApp are not attributed to it unless they are inside that recorded installation path.

## Compatibility

AppDock remains compatible with the existing DApp and widget contracts. DReader 2.0.3 remains a separate Store DApp release and is not modified by this core update.

## Validation

Lua 5.1 syntax checks passed. AppDock DApp, core, File Manager, theme/AppStore, and storage regression tests passed.
