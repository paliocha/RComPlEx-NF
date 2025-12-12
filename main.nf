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
    tuple val(tissue), val("${sp1}_${sp2}"), emit: pair_id
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
    tuple val(tissue), val(pair_id)

    output:
    tuple val(tissue), val(pair_id), path("01_filtered_data.RData"), emit: filtered_data

    script:
    """
    #!/bin/bash
    set -e

    # Step 1: Load and filter data (paths translated at runtime by R scripts, R from container)
    Rscript "${projectDir}/scripts/rcomplex_01_load_filter.R" \\
        --tissue ${tissue} \\
        --pair_id ${pair_id} \\
        --config "${projectDir}/config/pipeline_config.yaml" \\
        --workdir "${params.workdir}" \\
        --outdir .
    """
}

process RCOMPLEX_02_COMPUTE_NETWORKS {
    label 'high_mem'
    tag "${tissue}:${pair_id}"
    cache 'lenient'  // Ignore resource changes for caching
    
    // Resources controlled by config (withName: RCOMPLEX_02_COMPUTE_NETWORKS)

    input:
    tuple val(tissue), val(pair_id), path(filtered_data)

    output:
    tuple val(tissue), val(pair_id), path(filtered_data), path("02_networks.RData"), emit: networks

    script:
    """
    #!/bin/bash
    set -e

    # Step 2: Compute networks (paths translated at runtime by R scripts, R from container)
    # Using ${task.cpus} CPUs for parallel computation
    Rscript "${projectDir}/scripts/rcomplex_02_compute_networks.R" \\
        --tissue ${tissue} \\
        --pair_id ${pair_id} \\
        --config "${projectDir}/config/pipeline_config.yaml" \\
        --workdir "${params.workdir}" \\
        --indir . \\
        --outdir . \\
        --cores ${task.cpus}
    """
}

process RCOMPLEX_03_NETWORK_COMPARISON {
    label 'high_mem'
    tag "${tissue}:${pair_id}"
    cache 'lenient'  // Ignore resource changes for caching
    
    // Resources controlled by config (withName: RCOMPLEX_03_NETWORK_COMPARISON)

    input:
    tuple val(tissue), val(pair_id), path(filtered_data), path(networks)

    output:
    tuple val(tissue), val(pair_id), path("03_${pair_id}.RData"), emit: comparison

    script:
    """
    #!/bin/bash
    set -e

    # Step 3: Network comparison (paths translated at runtime by R scripts, R from container)
    # Using ${task.cpus} CPUs for parallel ortholog comparison
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

process RCOMPLEX_04_SUMMARY_STATS {
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

process FIND_CLIQUES {
    label 'very_high_mem'
    tag "${tissue}"
    cache 'lenient'  // Ignore resource changes for caching
    publishDir "${params.outdir}/${tissue}", mode: 'move'
    
    // Resources controlled by config (withName: FIND_CLIQUES)

    input:
    tuple val(tissue), path(comparison_files)

    output:
    tuple val(tissue), path('coexpressolog_cliques_*.tsv'), emit: cliques
    tuple val(tissue), path('genes_*.txt'), emit: gene_lists

    script:
    """
    #!/bin/bash
    set -e

    # Create results directory structure matching original layout
    mkdir -p rcomplex_results/${tissue}/results

    # Extract pair_id from filename and create corresponding directories
    # Files are named: 03_Sp1_Sp2.RData -> extract pair_id = Sp1_Sp2
    for file in 03_*.RData; do
        # Extract pair_id: 03_Sp1_Sp2.RData -> Sp1_Sp2
        pair_id=\${file#03_}
        pair_id=\${pair_id%.RData}
        pair_dir="rcomplex_results/${tissue}/results/\${pair_id}"
        mkdir -p "\$pair_dir"
        ln -s "\$(realpath \$file)" "\$pair_dir/03_comparison.RData"
    done

    # Verify all files were linked correctly
    n_files=\$(ls 03_*.RData 2>/dev/null | wc -l)
    n_dirs=\$(ls rcomplex_results/${tissue}/results/ 2>/dev/null | wc -l)
    if [ \$n_files -ne \$n_dirs ]; then
        echo "ERROR: File count mismatch (files: \$n_files, directories: \$n_dirs)"
        exit 1
    fi

    # Run clique detection (paths translated at runtime by R scripts)
    Rscript "${projectDir}/scripts/find_coexpressolog_cliques.R" \\
        --tissue ${tissue} \\
        --config "${projectDir}/config/pipeline_config.yaml" \\
        --workdir "${params.workdir}" \\
        --outdir . \\
        --results_dir rcomplex_results/${tissue}/results

    # Move outputs from tissue subdirectory to current directory if present
    if [ -d "${tissue}" ]; then
        mv ${tissue}/* .
        rmdir ${tissue}
    fi
    """
}

process SUMMARY_REPORT {
    label 'medium_mem'
    tag "report"
    cache 'lenient'  // Ignore resource changes for caching
    publishDir "${params.outdir}", mode: 'move'
    
    // Resources controlled by config (label 'medium_mem')

    input:
    path clique_files

    output:
    path 'pipeline_summary.txt'

    script:
    def tissues_str = params.tissues instanceof String ? params.tissues : params.tissues.join(', ')
    """
    #!/bin/bash
    set -e

    cat > pipeline_summary.txt <<EOF
RComPlEx Pipeline Summary
=========================

Date: \$(date)
Nextflow version: ${workflow.nextflow.version}
Pipeline version: ${workflow.manifest.version}

Tissues analyzed: ${tissues_str}

Clique files generated:
EOF

    for file in coexpressolog_cliques_*.tsv; do
        if [ -f "\$file" ]; then
            n_cliques=\$(tail -n +2 "\$file" | wc -l)
            echo "  - \$file: \$n_cliques cliques" >> pipeline_summary.txt
        fi
    done

    echo "" >> pipeline_summary.txt
    echo "Gene lists generated:" >> pipeline_summary.txt

    for file in genes_*.txt; do
        if [ -f "\$file" ]; then
            n_genes=\$(wc -l < "\$file")
            echo "  - \$file: \$n_genes genes" >> pipeline_summary.txt
        fi
    done

    cat pipeline_summary.txt
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow {
    
    // Show help message if requested
    if (params.help) {
        helpMessage()
        System.exit(0)
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

    Resources:
      Max CPUs        : ${Runtime.runtime.availableProcessors()}
      Max memory      : ${Runtime.runtime.maxMemory() / 1024 / 1024 / 1024} GB

    ══════════════════════════════════════════════════════════════
    """.stripIndent()

    // Load species list from YAML config
    def config_file = new File("${params.config}")
    def config = new org.yaml.snakeyaml.Yaml().load(config_file.text)
    def all_species = (config.species.annual + config.species.perennial).collect {
        it.replaceAll(' ', '_')  // Convert "Brachypodium distachyon" -> "Brachypodium_distachyon"
    }

    // Create channel from tissues list - use Groovy-style iteration
    pair_tuples = Channel.fromList(tissues_list).flatMap { tissue ->
        def all_pairs = []
        // Generate all unique species pairs using Groovy range syntax
        (0..<all_species.size()).each { i ->
            ((i+1)..<all_species.size()).each { j ->
                all_pairs << tuple(tissue, all_species[i], all_species[j])
            }
        }

        // In test mode, limit to first 3 pairs per tissue
        if (params.test_mode) {
            log.info "TEST MODE: Limiting ${tissue} to first 3 pairs (of ${all_pairs.size()} total)"
            return all_pairs.take(3)
        } else {
            log.info "Processing ${all_pairs.size()} pairs for ${tissue}"
            return all_pairs
        }
    }

    // Process each pair in parallel
    PREPARE_PAIR(pair_tuples)

    // Run RComPlEx in modular steps for each pair
    // Step 1: Load and filter data
    RCOMPLEX_01_LOAD_FILTER(PREPARE_PAIR.out.pair_id)

    // Step 2: Compute co-expression networks
    RCOMPLEX_02_COMPUTE_NETWORKS(RCOMPLEX_01_LOAD_FILTER.out.filtered_data)

    // Step 3: Perform network comparisons
    RCOMPLEX_03_NETWORK_COMPARISON(RCOMPLEX_02_COMPUTE_NETWORKS.out.networks)

    // Step 4: Generate summary statistics and plots
    RCOMPLEX_04_SUMMARY_STATS(RCOMPLEX_03_NETWORK_COMPARISON.out.comparison)

    // Step 5: Collect all comparison RData files and find cliques
    // Use the comparison files directly, not summaries
    cliques_input = RCOMPLEX_03_NETWORK_COMPARISON.out.comparison
        .map { tissue, _pair_id, comparison_file -> tuple(tissue, comparison_file) }
        .groupTuple()

    FIND_CLIQUES(cliques_input)

    // 5. Generate summary report
    all_cliques = FIND_CLIQUES.out.cliques
        .map { _tissue, files -> files }
        .flatten()
        .collect()

    SUMMARY_REPORT(all_cliques)
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
