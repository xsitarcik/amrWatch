rule gtdbtk__classify:
    input:
        assembly="results/assembly/{sample}/assembly.fasta",
        gtdb=os.path.join(config["gtdb_dirpath"], "db"),
    output:
        directory("results/taxonomy/{sample}"),
    params:
        assembly_dir=lambda wildcards, input: os.path.dirname(input.assembly),
    threads: min(config["threads"]["gtdb__classify"], config["max_threads"])
    conda:
        "../envs/gtdbtk.yaml"
    resources:
        mem_mb=get_mem_mb_for_gtdb,
    log:
        "logs/taxonomy/gtdb_classify/{sample}.log",
    shell:
        "(export GTDBTK_DATA_PATH={input.gtdb:q} && gtdbtk classify_wf --genome_dir {params.assembly_dir} --cpus {threads}"
        " --extension fasta --out_dir {output} --mash_db {input.gtdb}) > {log} 2>&1"


checkpoint gtdbtk__parse_taxa:
    input:
        gtdb_outdir=directory("results/taxonomy/{sample}"),
    output:
        "results/taxonomy/{sample}/parsed_taxa.txt",
    params:
        gtdb_tsv=lambda wildcards, input: os.path.join(input.gtdb_outdir, "classify", "gtdbtk.bac120.summary.tsv"),
    conda:
        "../envs/coreutils.yaml"
    log:
        "logs/taxonomy/parse_taxa/{sample}.log",
    shell:
        '(cut -f2 {params.gtdb_tsv} | tail -n 1 | sed -e "s/.*;s__//") > {output} 2> {log}'
