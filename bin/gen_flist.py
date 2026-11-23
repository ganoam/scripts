#!/usr/bin/env python3
# Agent generated; human reviewed; output verified.
# FuseSoC filelist generator: emit the union of all source files used by
# a list of top-level cores, plus +incdir+ lines for the include dirs.
import argparse
import os
import sys

from fusesoc.config import Config
from fusesoc.coremanager import CoreManager, DependencyError
from fusesoc.edalizer import Edalizer
from fusesoc.librarymanager import Library
from fusesoc.vlnv import Vlnv


def read_toplevels(path):
    """One VLNV per line; blank lines and '#' comments ignored."""
    with open(path) as f:
        return [
            Vlnv(line.strip())
            for line in f
            if line.strip() and not line.startswith("#")
        ]


def main():
    parser = argparse.ArgumentParser(
        description="Emit the union of all files used by a list of top-level cores"
    )
    parser.add_argument(
        "toplevels",
        help="File with one top-level core VLNV per line",
    )
    parser.add_argument(
        "--cores-root",
        action="append",
        default=".",
        help="Directory containing cores (repeatable)",
    )
    parser.add_argument("--target", default="default")
    parser.add_argument("--tool", default=None)
    parser.add_argument("--build-root", default="build")
    args = parser.parse_args()

    flags = {"target": args.target}
    if args.tool:
        flags["tool"] = args.tool

    cm = CoreManager(Config())
    for i, root in enumerate(args.cores_root):
        cm.add_library(Library(f"lib{i}", root), [])

    all_files = {}
    incdirs = set()
    for vlnv in read_toplevels(args.toplevels):
        core = cm.get_core(vlnv)
        work_root = os.path.abspath(
            os.path.join( args.build_root, core.name.sanitized_name, args.target)
        )

        try:
            edam = Edalizer(
                toplevel=core.name,
                flags=flags,
                core_manager=cm,
                work_root=work_root,
                export_root=None,
            ).run()
            for f in edam["files"]:
                f["name"] = os.path.abspath(os.path.join(work_root, f["name"]))
                all_files[f["name"]] = f

            for f in edam["files"]:
                if f.get("is_include_file"):
                    # include_path overrides the file's own dir (already reparented)
                    rel = f.get("include_path") or os.path.dirname(f["name"])
                    incdirs.add(os.path.abspath(os.path.join(work_root, rel)))



        except DependencyError as e:
            print(f"Failed to resolve {e.value}:\n{e.msg}")


    for d in sorted(incdirs):
        print(f"+incdir+{d}")
    for name in sorted(all_files):
        print(name)



if __name__ == "__main__":
    main()
