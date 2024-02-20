from snakemake.utils import validate
import json
import re


configfile: "config/config.yaml"


validate(config, "../schemas/config.schema.yaml")


pepfile: config["pepfile"]


validate(pep.sample_table, "../schemas/samples.schema.yaml")


def validate_dynamic_config():
    if config["reads__trimming"]["adapter_removal"]["do"]:
        if not os.path.exists(config["reads__trimming"]["adapter_removal"]["adapters_fasta"]):
            adapter_file = config["reads__trimming"]["adapter_removal"]["adapters_fasta"]
            raise ValueError(f"Adapter removal is enabled, but the {adapter_file=} does not exist")


validate_dynamic_config()


def get_sample_names() -> list[str]:
    return list(pep.sample_table["sample_name"].values)


def sample_has_asssembly_as_input(sample: str) -> bool:
    try:
        assembly = pep.sample_table.loc[sample][["fasta"]]
        return True
    except KeyError:
        return False


def get_sample_names_with_reads_as_input() -> list[str]:
    return [sample for sample in get_sample_names() if not sample_has_asssembly_as_input(sample)]


def get_constraints() -> dict[str, list[str]]:
    return {"sample": "|".join(get_sample_names()), "pair": ["R1", "R2"]}


def get_first_fastq_for_sample_from_pep(sample: str, read_pair="fq1") -> str:
    return pep.sample_table.loc[sample][[read_pair]][0]


def get_fasta_for_sample_from_pep(sample: str) -> str:
    return pep.sample_table.loc[sample][["fasta"]][0]


with open(f"{workflow.basedir}/resources/gtdb_amrfinder.json", "r") as f:
    AMRFINDER_MAP = json.load(f)

with open(f"{workflow.basedir}/resources/gtdb_mlst.json", "r") as f:
    MLST_MAP = json.load(f)


def get_key_for_value_from_db(value: str, db: dict) -> str:
    # search species first
    for key in db:
        if "species" not in db[key]:
            continue
        pattern = f'{db[key]["genus"]} {db[key]["species"]}'
        if re.match(pattern, value):
            return key

    # search genus
    for key in db:
        if "species" in db[key]:
            continue
        if re.match(db[key]["genus"], value):
            return key
    raise KeyError


def get_parsed_taxa_from_gtdbtk_for_sample(sample: str):
    with checkpoints.checkpoint_parse_taxa_gtdbtk.get(sample=sample).output[0].open() as f:
        return f.read().strip()


def check_preassembly_QC_for_sample(sample: str) -> bool:
    with checkpoints.checkpoint_pre_assembly_QC.get(sample=sample).output[0].open() as f:
        return all([line.startswith(("PASS", "WARN")) for line in f.readlines()])


def check_assembly_construction_success_for_sample(sample: str):
    with checkpoints.checkpoint_assembly_construction.get(sample=sample).output[0].open() as f:
        return all([line.startswith(("PASS", "WARN")) for line in f.readlines()])


def check_all_checks_success_for_sample(sample: str):
    with checkpoints.checkpoint_request_post_assembly_checks_if_relevant.get(sample=sample).output[0].open() as f:
        header = f.readline()
        return all([line.startswith(("PASS", "WARN")) for line in f.readlines()])


def get_outputs():
    sample_names = get_sample_names()
    outputs = {
        "final_results": expand("results/checks/{sample}/.final_results_requested.tsv", sample=sample_names),
    }

    if samples_with_reads := get_sample_names_with_reads_as_input():
        if len(samples_with_reads) > 1:
            outputs["multiqc"] = "results/summary/multiqc.html"
        else:
            sample = samples_with_reads[0]
            outputs["qc"] = [
                f"results/reads/trimmed/fastqc/{sample}_R1/fastqc_data.txt",
                f"results/reads/trimmed/fastqc/{sample}_R2/fastqc_data.txt",
                f"results/kraken/{sample}.bracken",
            ]
    return outputs


def get_taxonomy_dependant_outputs(sample: str, taxa: str) -> list[str]:
    outputs = []
    if taxa.startswith("Klebsiella"):
        outputs.append("results/amr_detect/{sample}/kleborate.tsv")
    elif "Staphylococcus" in taxa and "aureus" in taxa:
        outputs.append("results/amr_detect/{sample}/spa_typer.tsv")
        outputs.append("results/amr_detect/{sample}/SCCmec.tsv")
    elif taxa.startswith("Escherichia") or taxa.startswith("Shigella"):
        outputs.append("results/amr_detect/{sample}/etoki_ebeis.tsv")
    elif taxa.startswith("Salmonella"):
        outputs.append("results/amr_detect/{sample}/sistr_serovar.tab")
        outputs.append("results/amr_detect/{sample}/seqsero_summary.tsv")
    return outputs


def infer_outputs_for_sample(wildcards):
    if check_all_checks_success_for_sample(wildcards.sample):
        taxa = get_parsed_taxa_from_gtdbtk_for_sample(wildcards.sample)

        return [
            "results/amr_detect/{sample}/amrfinder.tsv",
            "results/amr_detect/{sample}/mlst.tsv",
            "results/amr_detect/{sample}/abricate.tsv",
            "results/amr_detect/{sample}/rgi_main.txt",
            "results/amr_detect/{sample}/resfinder/ResFinder_results.txt",
            "results/plasmids/{sample}/mob_typer.txt",
            "results/checks/{sample}/qc_summary.tsv",
        ] + get_taxonomy_dependant_outputs(wildcards.sample, taxa)

    else:
        return "results/checks/{sample}/qc_summary.tsv"


### Wildcard handling #################################################################################################


def infer_assembly_fasta(wildcards) -> str:
    if sample_has_asssembly_as_input(wildcards.sample):
        return get_fasta_for_sample_from_pep(wildcards.sample)
    else:
        return "results/assembly/{sample}/assembly.fasta"


def infer_fastqs_for_trimming(wildcards) -> list[str]:
    return pep.sample_table.loc[wildcards.sample][["fq1", "fq2"]]


def infer_fastq_path_for_fastqc(wildcards):
    if wildcards.step != "original":
        return "results/reads/{step}/{sample}_{pair}.fastq.gz"
    if "pair" not in wildcards or wildcards.pair == "R1":
        return get_first_fastq_for_sample_from_pep(wildcards.sample, read_pair="fq1")
    elif wildcards.pair == "R2":
        return get_first_fastq_for_sample_from_pep(wildcards.sample, read_pair="fq2")


def get_organism_for_amrfinder(wildcards):
    taxa = get_parsed_taxa_from_gtdbtk_for_sample(wildcards.sample)
    try:
        matched_organism = get_key_for_value_from_db(taxa, AMRFINDER_MAP)
        return f"--organism {matched_organism}"
    except KeyError:
        print(f"Could not find organism {taxa} for sample {wildcards.sample} in amrfinder map")
        return ""


def get_taxonomy_for_mlst(wildcards):
    taxa = get_parsed_taxa_from_gtdbtk_for_sample(wildcards.sample)
    try:
        matched_organism = get_key_for_value_from_db(taxa, MLST_MAP)
        return f"--scheme {matched_organism}"
    except KeyError:
        print(f"Could not find organism {taxa} for sample {wildcards.sample} in MLST map")
        return ""


def get_taxonomy_for_resfinder(wildcards):
    taxa = get_parsed_taxa_from_gtdbtk_for_sample(wildcards.sample)
    return taxa.lower()


def infer_relevant_checks(wildcards):
    if sample_has_asssembly_as_input(wildcards.sample):
        return ["results/checks/{sample}/check_skipping.tsv"]

    checks = ["results/checks/{sample}/pre_assembly_summary.tsv"]

    if not check_preassembly_QC_for_sample(wildcards.sample):
        return checks

    if check_assembly_construction_success_for_sample(wildcards.sample) and not config["gtdb_hack"]:
        checks += [
            "results/checks/{sample}/assembly_quality.tsv",
            "results/checks/{sample}/coverage_check.tsv",
            "results/checks/{sample}/self_contamination_check.tsv",
        ]

    return checks


### Parameter parsing #################################################################################################


def get_unicycler_params():
    extra = f"--min_fasta_length {config['assembly__unicycler']['min_fasta_length']}"
    extra += f" --mode {config['assembly__unicycler']['bridging_mode']}"
    extra += f" --linear_seqs {config['assembly__unicycler']['linear_seqs']}"
    return extra


def parse_adapter_removal_params():
    args_lst = []
    adapters_file = config["reads__trimming"]["adapter_removal"]["adapters_fasta"]
    read_location = config["reads__trimming"]["adapter_removal"]["read_location"]

    if read_location == "front":
        paired_arg = "-G"
    elif read_location == "anywhere":
        paired_arg = "-B"
    elif read_location == "adapter":
        paired_arg = "-A"

    args_lst.append(f"--{read_location} file:{adapters_file} {paired_arg} file:{adapters_file}")

    if config["reads__trimming"]["adapter_removal"]["keep_trimmed_only"]:
        args_lst.append("--discard-untrimmed")

    args_lst.append(f"--action {config['reads__trimming']['adapter_removal']['action']}")
    args_lst.append(f"--overlap {config['reads__trimming']['adapter_removal']['overlap']}")
    args_lst.append(f"--times {config['reads__trimming']['adapter_removal']['times']}")
    args_lst.append(f"--error-rate {config['reads__trimming']['adapter_removal']['error_rate']}")
    return args_lst


def get_cutadapt_extra() -> list[str]:
    args_lst = []

    if value := config["reads__trimming"].get("shorten_to_length", None):
        args_lst.append(f"--length {value}")
    if value := config["reads__trimming"].get("cut_from_start_r1", None):
        args_lst.append(f"--cut {value}")
    if value := config["reads__trimming"].get("cut_from_start_r2", None):
        args_lst.append(f"-U {value}")
    if value := config["reads__trimming"].get("cut_from_end_r1", None):
        args_lst.append(f"--cut -{value}")
    if value := config["reads__trimming"].get("cut_from_end_r2", None):
        args_lst.append(f"-U -{value}")

    if value := config["reads__trimming"].get("max_n_bases", None):
        args_lst.append(f"--max-n {value}")
    if value := config["reads__trimming"].get("max_expected_errors", None):
        args_lst.append(f"--max-expected-errors {value}")
    if config["reads__trimming"].get("trim_N_bases_on_ends", None):
        args_lst.append(f"--trim-n")
    if config["reads__trimming"].get("nextseq_trimming_mode", None):
        value = config["reads__trimming"].get("quality_cutoff_from_3_end_r1", None)
        if value is None:
            raise ValueError("If nextseq_trimming_mode is set, quality_cutoff_from_3_end_r1 must be set as well")
        args_lst.append(f"--nextseq-trim={value}")

    if config["reads__trimming"]["adapter_removal"]["do"]:
        args_lst += parse_adapter_removal_params()

    return args_lst


def parse_paired_cutadapt_param(pe_config, param1, param2, arg_name) -> str:
    if param1 in pe_config:
        if param2 in pe_config:
            return f"{arg_name} {pe_config[param1]}:{pe_config[param2]}"
        else:
            return f"{arg_name} {pe_config[param1]}:"
    elif param2 in pe_config:
        return f"{arg_name} :{pe_config[param2]}"
    return ""


def parse_cutadapt_comma_param(config, param1, param2, arg_name) -> str:
    if param1 in config:
        if param2 in config:
            return f"{arg_name} {config[param2]},{config[param1]}"
        else:
            return f"{arg_name} {config[param1]}"
    elif param2 in config:
        return f"{arg_name} {config[param2]},0"
    return ""


def get_cutadapt_extra_pe() -> str:
    args_lst = get_cutadapt_extra()

    cutadapt_config = config["reads__trimming"]
    if parsed_arg := parse_paired_cutadapt_param(cutadapt_config, "max_length_r1", "max_length_r2", "--maximum-length"):
        args_lst.append(parsed_arg)
    if parsed_arg := parse_paired_cutadapt_param(cutadapt_config, "min_length_r1", "min_length_r2", "--minimum-length"):
        args_lst.append(parsed_arg)
    if qual_cut_arg_r1 := parse_cutadapt_comma_param(
        cutadapt_config, "quality_cutoff_from_3_end_r1", "quality_cutoff_from_5_end_r2", "--quality-cutoff"
    ):
        args_lst.append(qual_cut_arg_r1)
    if qual_cut_arg_r2 := parse_cutadapt_comma_param(
        cutadapt_config, "quality_cutoff_from_3_end_r1", "quality_cutoff_from_5_end_r2", "-Q"
    ):
        args_lst.append(qual_cut_arg_r2)
    return " ".join(args_lst)


### Resource handling #################################################################################################


def get_mem_mb_for_trimming(wildcards, attempt):
    return min(config["max_mem_mb"], config["resources"]["reads__trimming_mem_mb"] * attempt)


def get_mem_mb_for_fastqc(wildcards, attempt):
    return min(config["max_mem_mb"], config["resources"]["fastqc_mem_mb"] * attempt)


def get_mem_mb_for_unicycler(wildcards, attempt):
    return min(config["max_mem_mb"], config["resources"]["assembly__unicycler_mem_mb"] * attempt)


def get_mem_mb_for_gtdb(wildcards, attempt):
    return min(config["max_mem_mb"], config["resources"]["gtdb_classify__mem_mb"] * attempt)


def get_mem_mb_for_mapping_postprocess(wildcards, attempt):
    return min(config["max_mem_mb"], config["resources"]["mapping__mem_mb"] * attempt)


def get_mem_mb_for_mapping(wildcards, attempt):
    return min(config["max_mem_mb"], config["resources"]["mapping_postprocess__mem_mb"] * attempt)
