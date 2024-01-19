rule unicycler__assemble_reads_into_contigs:
    input:
        paired=["results/reads/trimmed/{sample}_R1.fastq.gz", "results/reads/trimmed/{sample}_R2.fastq.gz"],
    output:
        contigs="results/assembly/{sample}/assembly.fasta",
        gfa="results/assembly/{sample}/assembly.gfa",
    params:
        extra=get_unicycler_params(),
    threads: min(config["threads"]["assembly__unicycler"], config["max_threads"])
    resources:
        mem_mb=get_mem_mb_for_unicycler,
    log:
        "logs/assembly/unicycler/{sample}.log",
    wrapper:
        "v3.3.0/bio/unicycler"


rule bandage__visualise_contig_overlaps:
    input:
        "results/assembly/{sample}/assembly.gfa",
    output:
        report(
            "results/assembly/{sample}/bandage/bandage.svg",
            category="{sample}",
            labels={"Type": "Bandage"},
        ),
    params:
        dir=lambda wildcards, output: os.path.dirname(output[0]),
    log:
        "logs/assembly/bandage_svg/{sample}.log",
    conda:
        "../envs/bandage.yaml"
    shell:
        "(mkdir -p {params.dir} && Bandage image {input} {output}) > {log} 2>&1"


rule bandage__info:
    input:
        "results/assembly/{sample}/assembly.gfa",
    output:
        "results/assembly/{sample}/bandage/bandage.info",
    params:
        dir=lambda wildcards, output: os.path.dirname(output[0]),
    log:
        "logs/assembly/bandage_info/{sample}.log",
    conda:
        "../envs/bandage.yaml"
    shell:
        "(mkdir -p {params.dir} && Bandage info {input} > {output}) 2> {log}"
