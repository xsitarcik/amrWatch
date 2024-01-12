checkpoint assembly_constructed:
    input:
        "results/assembly/{sample}/assembly.gfa",
    output:
        "results/checks/{sample}/assembly_constructed.txt",
    conda:
        "../envs/coreutils.yaml"
    log:
        "logs/checks/assembly_constructed/{sample}.log",
    shell:
        "(([ -s {input} ] && echo 'PASS: Assembly is not empty') || echo 'FAIL: Assembly construction failed') > {output} 2> {log}"


rule request_bandage_if_assembly_exists:
    input:
        assembly_constructed="results/checks/{sample}/assembly_constructed.txt",
        optional_bandage_outputs=optional_bandage_outputs,
    output:
        temp("results/checks/{sample}/.bandage_requested.txt"),
    conda:
        "../envs/coreutils.yaml"
    log:
        "logs/checks/assembly/{sample}.log",
    shell:
        "touch {output} 2> {log}"


rule check_assembly_quality:
    input:
        "results/assembly/{sample}/bandage/bandage.info",
    output:
        "results/checks/{sample}/assembly_quality.txt",
    params:
        max_dead_ends=200,
        max_contigs=2000,
    conda:
        "../envs/python.yaml"
    log:
        "logs/checks/assembly_quality/{sample}.log",
    script:
        "../scripts/check_assembly_quality.py"


rule summary_all_checks:
    input:
        bandage_check_if_relevant,
        foreign_contamination="results/checks/{sample}/foreign_contamination.txt",
        assembly_check="results/checks/{sample}/assembly_constructed.txt",
    output:
        "results/checks/{sample}/summary.txt",
    log:
        "logs/checks/summary/{sample}.log",
    conda:
        "../envs/bracken.yaml"
    shell:
        "cat {input} > {output} 2>&1"
