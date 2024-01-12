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


# rule quast__evaluate_assembly:
#     input:
#         fasta="results/assembly/{sample}/assembly.fasta",
#     output:
#         pdf=report(
#             "results/assembly/{sample}/quast/report.pdf",
#             category="{sample}",
#             labels={"Type": "QUAST"},
#         ),
#         basic_reports=multiext("results/assembly/{sample}/quast/report.", "html", "tex", "txt", "tsv"),
#         transposed=multiext("results/assembly/{sample}/quast/transposed_report.", "tex", "txt", "tsv"),
#         basic_stats=directory("results/assembly/{sample}/quast/basic_stats/"),
#         icarus="results/assembly/{sample}/quast/icarus.html",
#         viewer="results/assembly/{sample}/quast/icarus_viewers/contig_size_viewer.html",
#         log="results/assembly/{sample}/quast/quast.log",
#     log:
#         "logs/quast/{sample}.log",
#     threads: min(config["threads"]["quast"], config["max_threads"])
#     params:
#         extra=get_quast_params(),
#     wrapper:
#         "v3.3.0/bio/quast"


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
        "logs/bandage/{sample}.log",
    conda:
        "../envs/bandage.yaml"
    shell:
        "mkdir -p {params.dir} && Bandage image {input} {output} > {log} 2>&1"


rule bandage__info:
    input:
        "results/assembly/{sample}/assembly.gfa",
    output:
        "results/assembly/{sample}/bandage/bandage.info",
    params:
        dir=lambda wildcards, output: os.path.dirname(output[0]),
    log:
        "logs/bandage/{sample}.log",
    conda:
        "../envs/bandage.yaml"
    shell:
        "mkdir -p {params.dir} && Bandage info {input} > {output} 2> {log}"
