import os
import sys

shell.prefix("source activate augur; ")
configfile: "config.json"

# Set snakemake directory
SNAKEMAKE_DIR = os.path.dirname(workflow.snakefile)

def _get_json_outputs_by_virus(config):
    outputs = []
    for virus in config["viruses"]:
        for lineage in config["viruses"][virus]:
            for resolution in config["viruses"][virus][lineage]["resolutions"]:
                for segment in config["viruses"][virus][lineage]["segments"]:
                    outputs.append("augur/%s/auspice/%s_%s_%s_%s_meta.json" % (virus, virus, lineage, segment, resolution))

    return outputs

rule all:
    input: _get_json_outputs_by_virus(config)

rule process_virus:
    input: "augur/{virus}/prepared/{virus}_{lineage}_{segment}_{resolution}.json"
    output: "augur/{virus}/auspice/{virus}_{lineage}_{segment}_{resolution}_meta.json"
    shell: "cd augur/{wildcards.virus} && python {wildcards.virus}.process.py -j {SNAKEMAKE_DIR}/{input} --no_mut_freqs --no_tree_freqs"

def _get_viruses_per_month(wildcards):
    """Return the number of viruses per month for the given virus, lineage, and
    resolution with a default value returned when no configuration is defined.
    """
    return config["viruses"][wildcards.virus][wildcards.lineage].get("viruses_per_month", {}).get(
        wildcards.resolution,
        config["defaults"]["viruses_per_month"][wildcards.resolution]
    )

def _get_sampling_by_virus_lineage(wildcards):
    """Return the type of sampling to use for the given virus and lineage. Use
    default if no specific sampling is defined.
    """
    return config["viruses"][wildcards.virus].get(
        "sampling",
        config["defaults"]["sampling"]
    )

def _get_segments_by_virus_lineage(wildcards):
    """Return the genomic segments to use for the given virus and lineage.
    """
    segments = config["viruses"][wildcards.virus][wildcards.lineage].get("segments")
    assert segments is not None, "Segments are not defined for %s/%s" % (wildcards.virus, wildcards.lineage)
    return " ".join(segments)

def _get_sequences_by_virus_lineage(wildcards):
    return ["fauna/data/%s_%s_%s.fasta" % (wildcards.virus, wildcards.lineage, segment)
            for segment in _get_segments_by_virus_lineage(wildcards).split()]

rule prepare_virus:
    input:
        sequences="fauna/data/{virus}_{lineage}_{segment}.fasta",
        titers="fauna/data/{virus}_{lineage}_titers.tsv"
    output: "augur/{virus}/prepared/{virus}_{lineage}_{segment}_{resolution}.json"
    params: viruses_per_month=_get_viruses_per_month, sampling=_get_sampling_by_virus_lineage
    shell: """cd augur/{wildcards.virus} && python {wildcards.virus}.prepare.py --lineage {wildcards.lineage} \
              --resolution {wildcards.resolution} --segments {wildcards.segment} --sampling {params.sampling} \
              --viruses_per_month_seq {params.viruses_per_month} --titers {SNAKEMAKE_DIR}/{input.titers} \
              --sequences {SNAKEMAKE_DIR}/{input.sequences}"""

rule download_virus_titers:
    output: "fauna/data/{virus}_{lineage}_titers.tsv"
    shell: "cd fauna && python tdb/download.py -db tdb -v {wildcards.virus} --subtype {wildcards.lineage} --select assay_type:hi --fstem {wildcards.virus}_{wildcards.lineage}"

def _get_locus(wildcards):
    return wildcards.segment.upper()

def _get_fauna_lineage(wildcards):
    """Prepend the 'seasonal_' prefix to seasonal flu strains for fauna when
    necessary.
    """
    if wildcards.virus == "flu" and wildcards.lineage in ["h3n2", "h1n1pdm", "vic", "yam"]:
        return "seasonal_%s" % wildcards.lineage
    else:
        return wildcards.lineage

rule download_virus_sequences:
    output: "fauna/data/{virus}_{lineage}_{segment}.fasta"
    params: locus=_get_locus, fauna_lineage=_get_fauna_lineage
    shell: "cd fauna && python vdb/{wildcards.virus}_download.py -db vdb -v {wildcards.virus} --select locus:{params.locus} lineage:{params.fauna_lineage} --fstem {wildcards.virus}_{wildcards.lineage}_{wildcards.segment}"
