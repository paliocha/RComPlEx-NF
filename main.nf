#!/usr/bin/env nextflow

/*
 * RComPlEx Pipeline - Nextflow Implementation
 * ============================================
 * Identifies conserved co-expressologs across species with different life habits
 * Processes tissues separately: root and leaf
 */

nextflow.enable.dsl=2

// ============================================================================
// Parameters
// ============================================================================

// All key parameters (workdir, outdir, tissues, container) are in nextflow.config
// Override with: --workdir /path --outdir /path --tissues root,leaf

// Help message
def helpMessage() {
    log.info"""
    ═══════════════════════════════════════════════════════════════
    RComPlEx Pipeline - Comparative Co-expression Network Analysis
    ═══════════════════════════════════════════════════════════════
    
    Usage:
        nextflow run main.nf [options]
    
    Required:
        None (uses defaults from config/pipeline_config.yaml)
    
    Optional:
        --tissues <tissue>     Tissues to analyze [default: root,leaf]
                               Use --tissues root or --tissues leaf for single tissue
        --test_mode            Run with first 3 pairs only [default: false]
        --run_unsigned         Run unsigned network analysis + polarity divergence [default: false]
        --workdir <path>       Working directory for intermediate files [default: ${projectDir}]
        --outdir <path>        Output directory for final results [default: ${projectDir}/results]
        -w <path>              Nextflow work directory for temp files [default: ./work]
        --config <path>        Config file [default: config/pipeline_config.yaml]
        --help                 Show this message and exit
    
    Profiles:
        -profile slurm         SLURM executor (default)
        -profile standard      Local executor
        -profile test          Test mode with limited pairs
    
    Examples:
        # Basic run
        nextflow run main.nf -profile slurm
        
        # Single tissue
        nextflow run main.nf -profile slurm --tissues root
        
        # Custom directories
        nextflow run main.nf -profile slurm --workdir /scratch/data --outdir /project/results
        
        # Custom Nextflow work directory (for temp files)
        nextflow run main.nf -profile slurm -w /scratch/work
        
        # Test mode
        nextflow run main.nf -profile test
        
        # Resume from cached steps
        nextflow run main.nf -resume
    
    ═══════════════════════════════════════════════════════════════
    """.stripIndent()
}

// ============================================================================
// Process Definitions
// ============================================================================

process PREPARE_PAIR {
    label 'low_mem'
    tag "${tissue}:${sp1}_${sp2}"
    cache 'lenient'  // Ignore resource changes for caching
    // OPTIMIZED: Use copy instead of symlink to avoid cross-filesystem issues
    publishDir "${params.workdir}/rcomplex_data/${tissue}/pairs/${sp1}_${sp2}", mode: 'copy', overwrite: true
    
    // Resources controlled by config (label 'low_mem')

    input:
    tuple val(tissue), val(sp1), val(sp2)

    output:
    tuple val(tissue), val("${sp1}_${sp2}"), val(sp1), val(sp2), emit: pair_id
    path "*.RData", emit: data_files
    path "*.txt", emit: expr_files
    path "config.R", emit: config_file
    path "pair_stats.tsv", emit: stats_file, optional: true

    script:
    """
    #!/bin/bash
    set -e

    # Prepare single pair (paths translated at runtime by R scripts)
    Rscript "${projectDir}/scripts/prepare_single_pair.R" \\
        --tissue ${tissue} \\
        --sp1 ${sp1} \\
        --sp2 ${sp2} \\
        --config "${projectDir}/config/pipeline_config.yaml" \\
        --workdir "${params.workdir}"
    """
}

process RCOMPLEX_01_LOAD_FILTER {
    label 'low_mem'
    tag "${tissue}:${pair_id}"
    cache 'lenient'  // Ignore resource changes for caching
    
    // Resources controlled by config (label 'low_mem')

    input:
    tuple val(tissue), val(pair_id), val(species1), val(species2)

    output:
    tuple val(tissue), val(pair_id), val(species1), val(species2), path("01_filtered_data.RData"), emit: filtered_data

    script:
    """
    #!/bin/bash
    set -e

    # Step 1: Load and filter data to shared orthologs
    Rscript "${projectDir}/scripts/rcomplex_01_load_filter.R" \
        --tissue ${tissue} \
        --pair_id ${pair_id} \
        --config "${projectDir}/config/pipeline_config.yaml" \
        --workdir "${params.workdir}" \
        --outdir .
    """
}

process RCOMPLEX_02_COMPUTE_SPECIES_NETWORKS {
    label 'high_mem'
    tag "${tissue}:${species}"
    cache 'lenient'
    
    // Resources controlled by config - similar to old RCOMPLEX_02 but per species

    input:
    tuple val(tissue), val(species)

    output:
    tuple val(tissue), val(species), path("02_network_signed.qs2"), emit: network_signed
    tuple val(tissue), val(species), path("02_network_unsigned.qs2"), emit: network_unsigned, optional: true

    script:
    """
    #!/bin/bash
    set -e

    # Step 2: Compute species co-expression network
    Rscript "${projectDir}/scripts/rcomplex_02_compute_species_network.R" \\
        --tissue ${tissue} \\
        --species ${species} \\
        --config "${projectDir}/config/pipeline_config.yaml" \\
        --workdir "${params.workdir}" \\
        --outdir . \\
        --cores ${task.cpus}
    """
}

process RCOMPLEX_03_LOAD_AND_FILTER_NETWORKS {
    label 'low_mem'
    tag "${tissue}:${pair_id}"
    cache 'lenient'
    
    // Lightweight process - just loads and filters pre-computed matrices

    input:
    tuple val(tissue), val(pair_id), val(species1), val(species2), path(step1_dir),
          path(net1_signed, stageAs: 'sp1_net_signed.qs2'), 
          path(net2_signed, stageAs: 'sp2_net_signed.qs2')

    output:
    tuple val(tissue), val(pair_id), path("02_networks_signed.qs2"), emit: networks_signed

    script:
    """
    #!/bin/bash
    set -e

    # Extract directory path (step1_dir is the RData file, but script needs the directory)
    indir_path=\$(dirname "${step1_dir}")

    # Step 3: Load pre-computed networks and filter to pair orthologs (signed only)
    Rscript "${projectDir}/scripts/rcomplex_03_load_and_filter_networks.R" \\
        --tissue ${tissue} \\
        --pair_id ${pair_id} \\
        --species1 ${species1} \\
        --species2 ${species2} \\
        --net1_signed ${net1_signed} \\
        --net2_signed ${net2_signed} \\
        --indir "\${indir_path}" \\
        --outdir . \\
        --signed_only
    """
}

// Unsigned version of the filter process (only runs when --run_unsigned is set)
process RCOMPLEX_03_LOAD_AND_FILTER_NETWORKS_UNSIGNED {
    label 'low_mem'
    tag "${tissue}:${pair_id}"
    cache 'lenient'

    input:
    tuple val(tissue), val(pair_id), val(species1), val(species2), path(step1_dir),
          path(net1_unsigned, stageAs: 'sp1_net_unsigned.qs2'), 
          path(net2_unsigned, stageAs: 'sp2_net_unsigned.qs2')

    output:
    tuple val(tissue), val(pair_id), path("02_networks_unsigned.qs2"), emit: networks_unsigned

    script:
    """
    #!/bin/bash
    set -e

    indir_path=\$(dirname "${step1_dir}")

    Rscript "${projectDir}/scripts/rcomplex_03_load_and_filter_networks.R" \\
        --tissue ${tissue} \\
        --pair_id ${pair_id} \\
        --species1 ${species1} \\
        --species2 ${species2} \\
        --net1_unsigned ${net1_unsigned} \\
        --net2_unsigned ${net2_unsigned} \\
        --indir "\${indir_path}" \\
        --outdir . \\
        --unsigned_only
    """
}

process RCOMPLEX_04_NETWORK_COMPARISON {
    label 'high_mem'
    tag "${tissue}:${pair_id}"
    cache 'lenient'  // Ignore resource changes for caching
    
    // Resources controlled by config (withName: RCOMPLEX_04_NETWORK_COMPARISON)

    input:
    tuple val(tissue), val(pair_id), path(networks)

    output:
    tuple val(tissue), val(pair_id), path("03_${pair_id}.RData"), emit: comparison

    script:
    """
    #!/bin/bash
    set -e

    # Step 4: Network comparison (formerly Step 3)
    Rscript "${projectDir}/scripts/rcomplex_03_network_comparison.R" \\
        --tissue ${tissue} \\
        --pair_id ${pair_id} \\
        --config "${projectDir}/config/pipeline_config.yaml" \\
        --workdir "${params.workdir}" \\
        --indir . \\
        --outdir . \\
        --cores ${task.cpus}
    """
}

// Unsigned comparison consuming unsigned MR networks
process RCOMPLEX_04_NETWORK_COMPARISON_UNSIGNED {
    label 'high_mem'
    tag "${tissue}:${pair_id}"
    cache 'lenient'  // Ignore resource changes for caching
    
    // Resources controlled by config (withName: RCOMPLEX_04_NETWORK_COMPARISON_UNSIGNED)

    input:
    tuple val(tissue), val(pair_id), path(networks_unsigned)

    output:
    tuple val(tissue), val(pair_id), path("03_${pair_id}_unsigned.RData"), emit: comparison_unsigned

    script:
    """
    #!/bin/bash
    set -e

    # Step 3 (unsigned): Network comparison using unsigned MR networks
    # Using ${task.cpus} CPUs for parallel ortholog comparison
    Rscript "${projectDir}/scripts/rcomplex_03_network_comparison.R" \
        --tissue ${tissue} \
        --pair_id ${pair_id} \
        --config "${projectDir}/config/pipeline_config.yaml" \
        --workdir "${params.workdir}" \
        --indir . \
        --outdir . \
        --cores ${task.cpus}
    """
}

process RCOMPLEX_05_SUMMARY_STATS {
    label 'low_mem'
    tag "${tissue}:${pair_id}"
    cache 'lenient'  // Ignore resource changes for caching
    // OPTIMIZED: Use copy mode for better cross-filesystem compatibility
    publishDir "${params.workdir}/rcomplex_data/${tissue}/results/${pair_id}", mode: 'copy', overwrite: true
    
    // Resources controlled by config (label 'low_mem')

    input:
    tuple val(tissue), val(pair_id), path(comparison)

    output:
    tuple val(tissue), path("04_summary_statistics.tsv"), emit: summary
    path("04_*.png"), emit: plots, optional: true

    script:
    """
    #!/bin/bash
    set -e

    # Step 4: Generate summary statistics (paths translated at runtime by R scripts, R from container)
    Rscript "${projectDir}/scripts/rcomplex_04_summary_stats.R" \\
        --tissue ${tissue} \\
        --pair_id ${pair_id} \\
        --workdir "${params.workdir}" \\
        --indir . \\
        --outdir .
    """
}

// ==============================================================================
// STREAMING CLIQUE DETECTION (replaces batched approach)
// ==============================================================================
// Two-pass streaming approach:
//   Pass 1: Build HOG -> files index (lightweight scan)
//   Pass 2: Process each HOG by loading only its relevant data
// Memory efficient: only one HOG's data in memory at a time.
// ==============================================================================

process FIND_CLIQUES_STREAMING {
    label 'high_mem'
    tag "${tissue}:${mode}"
    cache 'lenient'
    publishDir "${params.outdir}/${tissue}", mode: 'copy'
    
    input:
    tuple val(tissue), val(mode), path(comparison_files), path(n1_file)

    output:
    tuple val(tissue), val(mode), path("cliques${mode == 'unsigned' ? '_unsigned' : ''}.qs2"), emit: cliques_qs2
    tuple val(tissue), val(mode), path("cliques${mode == 'unsigned' ? '_unsigned' : ''}.csv"), emit: cliques_csv
    tuple val(tissue), val(mode), path("cliques${mode == 'unsigned' ? '_unsigned' : ''}_*.csv"), emit: cliques_by_lifehabit, optional: true

    script:
    def file_pattern = mode == 'signed' ? '03_comparison.RData' : '03_comparison_unsigned.RData'
    """
    #!/bin/bash
    set -e

    # Create results directory structure
    mkdir -p rcomplex_results/${tissue}/results

    # Link comparison files into expected structure
    for file in 03_*.RData; do
        # For signed mode, skip unsigned files; for unsigned mode, only process unsigned files
        if [[ "${mode}" == "signed" && "\$file" == *"_unsigned.RData" ]]; then
            continue
        fi
        if [[ "${mode}" == "unsigned" && "\$file" != *"_unsigned.RData" ]]; then
            continue
        fi
        
        # Extract pair_id from filename
        pair_id=\${file#03_}
        if [[ "${mode}" == "unsigned" ]]; then
            pair_id=\${pair_id%_unsigned.RData}
        else
            pair_id=\${pair_id%.RData}
        fi
        
        pair_dir="rcomplex_results/${tissue}/results/\${pair_id}"
        mkdir -p "\$pair_dir"
        ln -s "\$(realpath \$file)" "\$pair_dir/${file_pattern}"
    done

    Rscript "${projectDir}/scripts/find_cliques_streaming.R" \\
        --tissue ${tissue} \\
        --mode ${mode} \\
        --config "${projectDir}/config/pipeline_config.yaml" \\
        --workdir "${params.workdir}" \\
        --results_dir rcomplex_results/${tissue}/results \\
        --n1_file ${n1_file} \\
        --outdir .
    """
}

process POLARITY_DIVERGENCE {
    label 'low_mem'
    tag "${tissue}:${pair_id}"
    cache 'lenient'
    publishDir "${params.outdir}/${tissue}/polarity", mode: 'copy', overwrite: true

    input:
    tuple val(tissue), val(pair_id), path(signed_cmp), path(unsigned_cmp)

    output:
    tuple val(tissue), val(pair_id), path("polarity_divergence_${pair_id}.tsv"), emit: divergence_report

    script:
    """
    #!/bin/bash
    set -e

    Rscript "${projectDir}/scripts/polarity_divergence_report.R" \
        --tissue ${tissue} \
        --pair_id ${pair_id} \
        --signed ${signed_cmp} \
        --unsigned ${unsigned_cmp} \
        --outdir .
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {
    
    // Show help message if requested
    if (params.help) {
        helpMessage()
        exit 0
    }

    // Ensure params.tissues is always a list (handle both String and List input)
    def tissues_list = params.tissues instanceof String ? [params.tissues] : params.tissues

    // Print parameters
    log.info """
    ╔══════════════════════════════════════════════════════════════╗
    ║             RComPlEx Co-Expressolog Pipeline                 ║
    ╚══════════════════════════════════════════════════════════════╝

    Configuration:
      Config file     : ${params.config}
      Work directory  : ${params.workdir}
      Output directory: ${params.outdir}
      Tissues         : ${tissues_list.join(', ')}
      Test mode       : ${params.test_mode}
      Run unsigned    : ${params.run_unsigned}

    Resources:
      Max CPUs        : ${Runtime.runtime.availableProcessors()}
      Max memory      : ${Runtime.runtime.maxMemory() / 1024 / 1024 / 1024} GB

    ══════════════════════════════════════════════════════════════
    """.stripIndent()

    // Load species list from YAML config
    def config_file = file(params.config)
    def config = new org.yaml.snakeyaml.Yaml().load(config_file.text)
    def all_species = (config.species.annual + config.species.perennial).collect {
        it.replaceAll(' ', '_')  // Convert "Brachypodium distachyon" -> "Brachypodium_distachyon"
    }

    // ========================================================================
    // REFACTORED ARCHITECTURE: Per-species network computation
    // ========================================================================

    // Step 1: Create species-tissue tuples for network computation
    // Build tuples programmatically then create channel
    def species_tissue_list = []
    tissues_list.each { tissue ->
        all_species.each { species ->
            species_tissue_list << tuple(tissue, species)
        }
    }
    if (params.test_mode) {
        log.info "TEST MODE: Limiting to first 5 species-tissue combinations"
        species_tissue_list = species_tissue_list.take(5 * tissues_list.size())
    }
    species_tissue_tuples = Channel.of(*species_tissue_list)

    // Step 2: Compute co-expression networks once per species-tissue
    RCOMPLEX_02_COMPUTE_SPECIES_NETWORKS(species_tissue_tuples)

    // Step 3: Create pair tuples for comparisons
    // Build all pairs programmatically
    def all_pairs_list = []
    tissues_list.each { tissue ->
        (0..<all_species.size()).each { i ->
            ((i+1)..<all_species.size()).each { j ->
                all_pairs_list << tuple(tissue, all_species[i], all_species[j])
            }
        }
    }
    if (params.test_mode) {
        log.info "TEST MODE: Limiting to first 3 pairs per tissue"
        all_pairs_list = all_pairs_list.take(3 * tissues_list.size())
    } else {
        log.info "Processing ${all_pairs_list.size()} total pairs across all tissues"
    }
    pair_tuples = Channel.of(*all_pairs_list)

    // Step 4: Prepare pair-specific orthologs
    PREPARE_PAIR(pair_tuples)

    // Step 5: Load and filter data to shared orthologs
    RCOMPLEX_01_LOAD_FILTER(PREPARE_PAIR.out.pair_id)

    // Step 6: Load pre-computed networks and filter to pair orthologs
    // Join signed networks with pair metadata
    species_nets_signed = RCOMPLEX_02_COMPUTE_SPECIES_NETWORKS.out.network_signed
        .map { tissue, species, net_file -> tuple([tissue, species], net_file) }

    pair_with_nets_signed = RCOMPLEX_01_LOAD_FILTER.out.filtered_data
        .map { tissue, pair_id, species1, species2, step1_dir ->
            tuple([tissue, species1], [tissue, species2], tissue, pair_id, species1, species2, step1_dir)
        }
        .combine(species_nets_signed, by: 0)  // Join on [tissue, species1]
        .map { key1, key2, tissue, pair_id, species1, species2, step1_dir, net1_signed ->
            tuple(key2, tissue, pair_id, species1, species2, step1_dir, net1_signed)
        }
        .combine(species_nets_signed, by: 0)  // Join on [tissue, species2]
        .map { key2, tissue, pair_id, species1, species2, step1_dir, net1_signed, net2_signed ->
            tuple(tissue, pair_id, species1, species2, step1_dir, net1_signed, net2_signed)
        }

    // Always run signed network filtering
    RCOMPLEX_03_LOAD_AND_FILTER_NETWORKS(pair_with_nets_signed)

    // Step 7: Perform network comparisons
    RCOMPLEX_04_NETWORK_COMPARISON(RCOMPLEX_03_LOAD_AND_FILTER_NETWORKS.out.networks_signed)

    // Unsigned processing (optional - controlled by --run_unsigned flag)
    if (params.run_unsigned) {
        // Join unsigned networks with pair metadata
        species_nets_unsigned = RCOMPLEX_02_COMPUTE_SPECIES_NETWORKS.out.network_unsigned
            .map { tissue, species, net_file -> tuple([tissue, species], net_file) }

        pair_with_nets_unsigned = RCOMPLEX_01_LOAD_FILTER.out.filtered_data
            .map { tissue, pair_id, species1, species2, step1_dir ->
                tuple([tissue, species1], [tissue, species2], tissue, pair_id, species1, species2, step1_dir)
            }
            .combine(species_nets_unsigned, by: 0)
            .map { key1, key2, tissue, pair_id, species1, species2, step1_dir, net1_unsigned ->
                tuple(key2, tissue, pair_id, species1, species2, step1_dir, net1_unsigned)
            }
            .combine(species_nets_unsigned, by: 0)
            .map { key2, tissue, pair_id, species1, species2, step1_dir, net1_unsigned, net2_unsigned ->
                tuple(tissue, pair_id, species1, species2, step1_dir, net1_unsigned, net2_unsigned)
            }

        RCOMPLEX_03_LOAD_AND_FILTER_NETWORKS_UNSIGNED(pair_with_nets_unsigned)
        RCOMPLEX_04_NETWORK_COMPARISON_UNSIGNED(RCOMPLEX_03_LOAD_AND_FILTER_NETWORKS_UNSIGNED.out.networks_unsigned)
    }

    // Step 8: Generate summary statistics and plots (formerly Step 4)
    RCOMPLEX_05_SUMMARY_STATS(RCOMPLEX_04_NETWORK_COMPARISON.out.comparison)

    // Step 9: STREAMING CLIQUE DETECTION (two-pass approach)
    // Create N1 file channel once
    ch_n1_file = Channel.value(file(params.n1_file))
    
    // Prepare signed comparison files grouped by tissue
    cliques_input_signed = RCOMPLEX_04_NETWORK_COMPARISON.out.comparison
        .map { tissue, _pair_id, comparison_file -> tuple(tissue, comparison_file) }
        .groupTuple()
        .map { tissue, files -> tuple(tissue, "signed", files) }
        .combine(ch_n1_file)

    // Conditionally add unsigned clique detection
    if (params.run_unsigned) {
        // Prepare unsigned comparison files grouped by tissue
        cliques_input_unsigned = RCOMPLEX_04_NETWORK_COMPARISON_UNSIGNED.out.comparison_unsigned
            .map { tissue, _pair_id, comparison_file -> tuple(tissue, comparison_file) }
            .groupTuple()
            .map { tissue, files -> tuple(tissue, "unsigned", files) }
            .combine(ch_n1_file)

        // Run streaming clique detection for both signed and unsigned
        cliques_input_all = cliques_input_signed.mix(cliques_input_unsigned)
        FIND_CLIQUES_STREAMING(cliques_input_all)

        // Polarity divergence (diagnostic - requires both signed and unsigned)
        divergence_input = RCOMPLEX_03_LOAD_AND_FILTER_NETWORKS.out.networks_signed
            .map { tissue, pair_id, networks_signed -> tuple([tissue, pair_id], networks_signed) }
            .join(
                RCOMPLEX_03_LOAD_AND_FILTER_NETWORKS_UNSIGNED.out.networks_unsigned
                    .map { tissue, pair_id, networks_unsigned -> tuple([tissue, pair_id], networks_unsigned) }
            )
            .map { key, signed_net, unsigned_net -> tuple(key[0], key[1], signed_net, unsigned_net) }

        POLARITY_DIVERGENCE(divergence_input)
    } else {
        // Signed-only clique detection
        FIND_CLIQUES_STREAMING(cliques_input_signed)
    }
}

// ============================================================================
// Workflow Event Handlers (Top-Level Scope)
// NOTE: workflow.onComplete and workflow.onError MUST be defined at top level
// These are global event handlers, not workflow statements - see Nextflow docs
// The linter incorrectly flags these, but they are valid and required DSL2
// ============================================================================

workflow.onComplete {
    def summary = [:]
    summary['Pipeline'] = workflow.manifest.name
    summary['Version'] = workflow.manifest.version
    summary['Run Name'] = workflow.runName
    summary['Session ID'] = workflow.sessionId
    summary['Success'] = workflow.success
    summary['Exit status'] = workflow.exitStatus
    summary['Started'] = workflow.start
    summary['Completed'] = workflow.complete
    summary['Duration'] = workflow.duration
    summary['CPU hours'] = workflow.stats.getComputeTimeFmt()
    summary['Results'] = params.outdir
    summary['Work dir'] = workflow.workDir
    summary['Profile'] = workflow.profile
    summary['Container'] = params.container
    
    log.info """
    ══════════════════════════════════════════════════════════════
    Pipeline completed!
    Status    : ${workflow.success ? 'SUCCESS' : 'FAILED'}
    Started   : ${workflow.start}
    Completed : ${workflow.complete}
    Duration  : ${workflow.duration}
    CPU hours : ${workflow.stats.getComputeTimeFmt()}

    Results   : ${params.outdir}
    ══════════════════════════════════════════════════════════════
    """.stripIndent()
    
    // Write detailed summary to file
    def outDirPath = params.outdir.toString()
    def summaryFilePath = new File("${outDirPath}/pipeline_summary.txt")
    summaryFilePath.parentFile.mkdirs()
    
    // Delete if exists as directory (edge case)
    if (summaryFilePath.exists() && summaryFilePath.isDirectory()) {
        summaryFilePath.deleteDir()
    }
    
    summaryFilePath.text = summary.collect { k, v -> "${k.padRight(20)}: $v" }.join('\n')
}

workflow.onError {
    log.error "Pipeline execution failed: ${workflow.errorMessage}"
}
