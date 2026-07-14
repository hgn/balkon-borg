#!/usr/bin/env python3
"""Minimal parser for a KiCad .net netlist (as emitted by SKiDL / kicad-cli).

Just enough s-expression handling to pull out the component list and the nets.
Used by check-netlist-board.py and check-board-spec.py so both read the netlist
the same way. Standard library only, runs under any python3.
"""

from __future__ import annotations

import re
from pathlib import Path

_TOKEN = re.compile(r'\(|\)|"(?:[^"\\]|\\.)*"|[^\s()]+')


def _parse_sexpr(text: str) -> list:
    """Return the top-level s-expressions of the file as nested lists."""
    tokens = _TOKEN.findall(text)

    def build(it) -> list:
        node: list = []
        for tok in it:
            if tok == "(":
                node.append(build(it))
            elif tok == ")":
                return node
            elif tok.startswith('"'):
                node.append(tok[1:-1])
            else:
                node.append(tok)
        return node

    it = iter(tokens)
    top: list = []
    for tok in it:
        if tok == "(":
            top.append(build(it))
    return top


def _find(node: list, key: str):
    for child in node:
        if isinstance(child, list) and child and child[0] == key:
            return child
    return None


def _findall(node: list, key: str) -> list:
    return [c for c in node if isinstance(c, list) and c and c[0] == key]


def _val(node: list, key: str) -> str | None:
    child = _find(node, key)
    return child[1] if child and len(child) > 1 else None


def parse(path: str | Path) -> tuple[dict[str, str], dict[str, set[tuple[str, str]]]]:
    """Parse a .net file.

    Returns (components, nets):
      components: ref -> value            e.g. {"R1": "1k", "Q1": "BC337"}
      nets:       netname -> {(ref, pin)} e.g. {"GND": {("J2","14"), ...}}
    """
    top = _parse_sexpr(Path(path).read_text())
    export = top[0] if top else []

    comps: dict[str, str] = {}
    comps_node = _find(export, "components")
    if comps_node:
        for comp in _findall(comps_node, "comp"):
            ref = _val(comp, "ref")
            if ref is not None:
                comps[ref] = _val(comp, "value") or ""

    nets: dict[str, set[tuple[str, str]]] = {}
    nets_node = _find(export, "nets")
    if nets_node:
        for net in _findall(nets_node, "net"):
            name = _val(net, "name") or ""
            pads: set[tuple[str, str]] = set()
            for node in _findall(net, "node"):
                ref, pin = _val(node, "ref"), _val(node, "pin")
                if ref is not None and pin is not None:
                    pads.add((ref, pin))
            nets[name] = pads

    return comps, nets
