include { SVANALYZER_SVBENCHMARK                } from '../../../modules/nf-core/svanalyzer/svbenchmark/main'
include { TABIX_TABIX as TABIX_FPS              } from '../../../modules/nf-core/tabix/tabix/main'
include { TABIX_TABIX as TABIX_FNS              } from '../../../modules/nf-core/tabix/tabix/main'
include { BCFTOOLS_ISEC as BCFTOOLS_ISEC_QUERY  } from '../../../modules/nf-core/bcftools/isec/main'
include { BCFTOOLS_ISEC as BCFTOOLS_ISEC_TRUTH  } from '../../../modules/nf-core/bcftools/isec/main'

workflow SVANALYZER_BENCHMARK {

    take:
    ch_input  // channel: [ val(meta), path(test_vcf), path(test_tbi), path(truth_vcf), path(truth_tbi), path(bed) ]
    ch_fasta  // channel: [ val(meta2), path(fasta) ]
    ch_fai    // channel: [ val(meta3), path(fai) ]

    main:

    // Run svanalyzer benchmark to compare test VCF against truth VCF
    SVANALYZER_SVBENCHMARK(ch_input, ch_fasta, ch_fai)

    // Index FP and FN outputs for bcftools isec
    TABIX_FPS(SVANALYZER_SVBENCHMARK.out.fps)
    TABIX_FNS(SVANALYZER_SVBENCHMARK.out.fns)

    // Subtract FPs from test/query VCF to find true positives in query (TP_comp)
    ch_input
        .map { meta, test_vcf, test_tbi, _truth_vcf, _truth_tbi, bed -> [meta, test_vcf, test_tbi, bed] }
        .join(SVANALYZER_SVBENCHMARK.out.fps)
        .join(TABIX_FPS.out.index)
        .map { meta, test_vcf, test_tbi, bed, fp_vcf, fp_tbi ->
            [meta, [test_vcf, fp_vcf], [test_tbi, fp_tbi], [], [], bed]
        }
        .set { ch_isec_query }

    BCFTOOLS_ISEC_QUERY(ch_isec_query)

    // Subtract FNs from truth VCF to find true positives in truth (TP_base)
    ch_input
        .map { meta, _test_vcf, _test_tbi, truth_vcf, truth_tbi, bed -> [meta, truth_vcf, truth_tbi, bed] }
        .join(SVANALYZER_SVBENCHMARK.out.fns)
        .join(TABIX_FNS.out.index)
        .map { meta, truth_vcf, truth_tbi, bed, fn_vcf, fn_tbi ->
            [meta, [truth_vcf, fn_vcf], [truth_tbi, fn_tbi], [], [], bed]
        }
        .set { ch_isec_truth }

    BCFTOOLS_ISEC_TRUTH(ch_isec_truth)

    // Extract complement VCF from isec output directories
    ch_tp_comp = BCFTOOLS_ISEC_QUERY.out.results
        .map { meta, dir -> [meta, file("${dir}/0000.vcf.gz")] }
    ch_tp_base = BCFTOOLS_ISEC_TRUTH.out.results
        .map { meta, dir -> [meta, file("${dir}/0000.vcf.gz")] }

    emit:
    fps       = SVANALYZER_SVBENCHMARK.out.fps        // channel: [ val(meta), path(vcf) ]
    fns       = SVANALYZER_SVBENCHMARK.out.fns        // channel: [ val(meta), path(vcf) ]
    tp_comp   = ch_tp_comp                             // channel: [ val(meta), path(vcf) ]
    tp_base   = ch_tp_base                             // channel: [ val(meta), path(vcf) ]
    distances = SVANALYZER_SVBENCHMARK.out.distances   // channel: [ val(meta), path(distances) ]
    report    = SVANALYZER_SVBENCHMARK.out.report      // channel: [ val(meta), path(report) ]
}
