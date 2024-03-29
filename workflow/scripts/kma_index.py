import os
import sys

from snakemake.shell import shell


def get_suffix() -> str:
    return snakemake.params.suffix


def get_resfinder_paths() -> list[str]:
    return snakemake.output.resfinder_out


def get_pointfinder_paths() -> list[str]:
    return snakemake.output.pointfinder_out


def get_disinfinder_paths() -> list[str]:
    return snakemake.output.disinfinder_out


suffix = get_suffix()
resfinder_names = [os.path.basename(value).removesuffix(suffix) for value in get_resfinder_paths()]
pointfinder_names = [os.path.basename(value).removesuffix(suffix) for value in get_pointfinder_paths()]
disinfinder_names = [os.path.basename(value).removesuffix(suffix) for value in get_disinfinder_paths()]

sys.stderr = open(snakemake.log[0], "w")

for name in resfinder_names:
    print(f"Processing resfinder: {name}", file=sys.stderr)
    shell(
        "kma_index -i {snakemake.params.resfinder_db_dir}/{name}.fsa -o {snakemake.params.resfinder_db_dir}/{name} >> {snakemake.log} 2>&1"
    )

for name in disinfinder_names:
    print(f"Processing disinfinder: {name}", file=sys.stderr)
    shell(
        "kma_index -i {snakemake.params.disinfinder_db_dir}/{name}.fsa -o {snakemake.params.disinfinder_db_dir}/{name} >> {snakemake.log} 2>&1"
    )

for name in pointfinder_names:
    print(f"Processing pointfinder: {name}", file=sys.stderr)
    shell(
        "kma_index -i {snakemake.params.pointfinder_db_dir}/{name}/*.fsa -o {snakemake.params.pointfinder_db_dir}/{name}/{name} >> {snakemake.log} 2>&1"
    )
