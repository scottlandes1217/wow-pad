#!/bin/zsh
# Build wow-pad and code-sign it. With an "Apple Development" certificate the signature is stable, so
# macOS keeps its Accessibility permission across rebuilds; ad-hoc signed, re-grant after rebuilding.
set -e
cd ${0:A:h}
swiftc -O -swift-version 5 pad.swift -o wow-pad
identity=$(security find-identity -v -p codesigning | grep -m1 -o '"Apple Development[^"]*"' | tr -d '"' || true)
codesign -f -s "${identity:--}" -i "${WOW_PAD_ID:-wow-pad}" wow-pad
./wow-pad --selftest
if command -v luac >/dev/null; then luac -p addon/PadBar/PadBar.lua; fi   # (Lua syntax, if Lua is installed)
