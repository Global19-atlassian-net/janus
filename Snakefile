import os
import sys

shell.prefix("source activate augur; ")
configfile: "config.json"
localrules: download_virus_lineage_titers, download_virus_lineage_sequences, download_complete_virus_sequences
wildcard_constraints:
    virus="[a-zA-Z0-9]+"

# Set snakemake directory
SNAKEMAKE_DIR = os.path.dirname(workflow.snakefile)

#
# Helper functions
#

def _get_json_outputs_by_virus(config):
    """Prepare a list of outputs for all combination of viruses, lineages, and
    segments defined in the configuration.
    """
    outputs = []
    for virus in config["viruses"]:
        if "lineages" in config["viruses"][virus]:
            virus_config = config["viruses"][virus]
            for lineage in virus_config["lineages"]:
                for resolution in virus_config[lineage]["resolutions"]:
                    for segment in virus_config[lineage]["segments"]:
                        outputs.append("augur/%s/auspice/%s_%s_%s_%s_meta.json" % (virus, virus, lineage, segment, resolution))
        else:
            outputs.append("augur/%s/auspice/%s_meta.json" % (virus, virus))

    return outputs

def _get_viruses_per_month(wildcards):
    """Return the number of viruses per month for the given virus, lineage, and
    resolution with a default value returned when no configuration is defined.

    Check first for lineage- and resolution-specific viruses per month (as with
    flu). Then check for virus-specific viruses per month. If no value has been
    defined, return 0.
    """
    virus_config = config["viruses"][wildcards.virus]
    if (hasattr(wildcards, "lineage") and
        wildcards.lineage in virus_config and
        "viruses_per_month" in virus_config[wildcards.lineage] and
        wildcards.resolution in virus_config[wildcards.lineage]["viruses_per_month"]):
        viruses_per_month = virus_config[wildcards.lineage]["viruses_per_month"][wildcards.resolution]
    elif "viruses_per_month" in virus_config:
        viruses_per_month = virus_config["viruses_per_month"]
    else:
        viruses_per_month = 0

    return viruses_per_month

def _get_resolution_argument_by_virus_lineage(wildcards):
    """Return the resolution to use for the given virus and lineage. The
    default is not to define any resolution argument.
    """
    if hasattr(wildcards, "resolution") and wildcards.resolution != "all":
        return "--resolution %s" % wildcards.resolution
    else:
        return ""

def _get_sampling_argument_by_virus_lineage(wildcards):
    """Return the type of sampling to use for the given virus and lineage. The
    default is not to define any sampling argument.
    """
    sampling = config["viruses"][wildcards.virus].get(wildcards.lineage, {}).get("sampling")
    if sampling is not None:
        return "--sampling %s" % sampling
    else:
        return ""

def _get_locus(wildcards):
    """Uppercase the requested segment name for fauna.
    """
    return wildcards.segment.upper()

def _get_fauna_lineage(wildcards):
    """Prepend the 'seasonal_' prefix to seasonal flu strains for fauna when
    necessary.
    """
    if wildcards.virus == "flu" and wildcards.lineage in ["h3n2", "h1n1pdm", "vic", "yam"]:
        return "seasonal_%s" % wildcards.lineage
    else:
        return wildcards.lineage

rule all:
    input: _get_json_outputs_by_virus(config)

#
# Prepare and process viruses by lineage.
#

rule process_virus_lineage:
    input: "augur/{virus}/prepared/{virus}_{lineage}_{segment}_{resolution}.json"
    output: "augur/{virus}/auspice/{virus}_{lineage}_{segment}_{resolution}_meta.json"
    benchmark: "benchmarks/process/{virus}_{lineage}_{segment}_{resolution}.txt"
    shell: "cd augur/{wildcards.virus} && python {wildcards.virus}.process.py -j {SNAKEMAKE_DIR}/{input} --no_mut_freqs --no_tree_freqs"

def _get_prepare_inputs_by_virus_lineage(wildcards):
    """Determine which inputs should be built for the given virus/lineage especially
    in the case when a virus may have titers available.
    """
    inputs = {"sequences": "fauna/data/{wildcards.virus}_{wildcards.lineage}_{wildcards.segment}.fasta".format(wildcards=wildcards)}

    if config["viruses"][wildcards.virus][wildcards.lineage].get("has_titers", False):
        inputs["titers"] = "fauna/data/{wildcards.virus}_{wildcards.lineage}_titers.tsv".format(wildcards=wildcards)

    return inputs

def _get_titers_argument_by_virus_lineage(wildcards, input):
    """Return a prepare argument for titers if the current virus/lineage has
    available titers.
    """
    if hasattr(input, "titers"):
        return "--titers %s" % os.path.join(SNAKEMAKE_DIR, input.titers)
    else:
        return ""

rule prepare_virus_lineage:
    input: unpack(_get_prepare_inputs_by_virus_lineage)
    output: "augur/{virus}/prepared/{virus}_{lineage}_{segment}_{resolution}.json"
    params:
        viruses_per_month=_get_viruses_per_month,
        resolution=_get_resolution_argument_by_virus_lineage,
        sampling=_get_sampling_argument_by_virus_lineage,
        titers=_get_titers_argument_by_virus_lineage
    benchmark: "benchmarks/prepare/{virus}_{lineage}_{segment}_{resolution}.txt"
    shell: """cd augur/{wildcards.virus} && python {wildcards.virus}.prepare.py --lineage {wildcards.lineage} \
              {params.resolution} --segments {wildcards.segment} {params.sampling} \
              --viruses_per_month_seq {params.viruses_per_month} {params.titers} \
              --sequences {SNAKEMAKE_DIR}/{input.sequences}"""

#
# Prepare and process complete viruses without lineages.
#

rule process_complete_virus:
    input: "augur/{virus}/prepared/{virus}.json"
    output: "augur/{virus}/auspice/{virus}_meta.json"
    benchmark: "benchmarks/process/{virus}.txt"
    shell: "cd augur/{wildcards.virus} && python {wildcards.virus}.process.py"

rule prepare_complete_virus:
    input: sequences="fauna/data/{virus}.fasta"
    output: "augur/{virus}/prepared/{virus}.json"
    params: viruses_per_month=_get_viruses_per_month
    benchmark: "benchmarks/prepare/{virus}.txt"
    shell: """cd augur/{wildcards.virus} && python {wildcards.virus}.prepare.py #\
              #--viruses_per_month_seq {params.viruses_per_month} \
              #--sequences {SNAKEMAKE_DIR}/{input.sequences}"""

#
# Download data with fauna
#

rule download_virus_lineage_titers:
    output: "fauna/data/{virus}_{lineage}_titers.tsv"
    benchmark: "benchmarks/fauna_{virus}_{lineage}_titers.txt"
    shell: "cd fauna && python tdb/download.py -db tdb -v {wildcards.virus} --subtype {wildcards.lineage} --select assay_type:hi --fstem {wildcards.virus}_{wildcards.lineage}"

rule download_virus_lineage_sequences:
    output: "fauna/data/{virus}_{lineage}_{segment}.fasta"
    params: locus=_get_locus, fauna_lineage=_get_fauna_lineage
    benchmark: "benchmarks/fauna_{virus}_{lineage}_{segment}_fasta.txt"
    shell: "cd fauna && python vdb/{wildcards.virus}_download.py -db vdb -v {wildcards.virus} --select locus:{params.locus} lineage:{params.fauna_lineage} --fstem {wildcards.virus}_{wildcards.lineage}_{wildcards.segment}"

rule download_complete_virus_sequences:
    output: "fauna/data/{virus}.fasta"
    benchmark: "benchmarks/fauna_{virus}_fasta.txt"
    shell: "cd fauna && python vdb/{wildcards.virus}_download.py -db vdb -v {wildcards.virus} --fstem {wildcards.virus} --resolve_method choose_genbank"

#
# Clean up output files for quick rebuild without redownload
#

rule clean:
    params: viruses=list(config["viruses"].keys())
    shell: """for virus in {params.viruses}
do
    rm -f augur/$virus/prepared/$virus*;
    rm -f augur/$virus/processed/$virus*;
    rm -f augur/$virus/auspice/$virus*;
done"""
