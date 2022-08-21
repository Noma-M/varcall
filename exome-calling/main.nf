#!/usr/bin/env nextflow

if (params.build == "b37") {
  chroms = "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,X,Y,MT".split(',')
} else if (params.build == "b38"){
    chroms = "chr1,chr2,chr3,chr4,chr5,chr6,chr7,chr8,chr9,chr10,chr11,chr12,chr13,chr14,chr15,chr16,chr17,chr18,chr19,chr20,chr21,chr22,chrX,chrY,chrM".split(',')
} else {
    println "\n============================================================================================="
    println "Please specify a genome build (b37 or b38)!"
    println "=============================================================================================\n"
    exit 1
}

db = file(params.db_path)
db_import = params.db_import

ref_seq = Channel.fromPath(params.ref_seq).toList()
ref_seq_index = Channel.fromPath(params.ref_seq_index).toList()
ref_seq_dict = Channel.fromPath(params.ref_seq_dict).toList()

process log_tool_version_gatk {
    tag { "${params.project_name}.ltVG" }
    echo true
    publishDir "${params.out_dir}/${params.cohort_id}/exome-calling", mode: 'copy', overwrite: false
    label 'gatk'

    output:
    file("tool.gatk.version") into tool_version_gatk

    script:
    mem = task.memory.toGiga() - 3
    """
    gatk --java-options "-XX:+UseSerialGC -Xss456k -Xms500m -Xmx${mem}g" --version > tool.gatk.version 2>&1
    """
}

if (db_import == "no") {

Channel.from( file(params.gvcf) )
        .set{ gvcf_ch }

  process run_genotype_gvcf_on_genome_gvcf {
      tag { "${params.project_name}.${params.cohort_id}.${chr}.rGGoG" }
      memory { 16.GB * task.attempt }  
      publishDir "${params.out_dir}/${params.cohort_id}/exome-calling", mode: 'copy', overwrite: false
      label 'gatk'
    
      input:
      val gvcf from gvcf_ch
      file ref_seq
      file ref_seq_index
      file ref_seq_dict
      each chr from chroms
  
      output:
      set chr, file("${params.cohort_id}.${chr}.vcf.gz"), file("${params.cohort_id}.${chr}.vcf.gz.tbi") into gg_vcf_set
      file("${params.cohort_id}.${chr}.vcf.gz") into gg_vcf
  
      script:
        mem = task.memory.toGiga() - 4
        call_conf = 30 // set default
        if ( params.sample_coverage == "high" )
          call_conf = 30
        else if ( params.sample_coverage == "low" )
          call_conf = 10
      """
      gatk --java-options  "-XX:+UseSerialGC -Xms4g -Xmx${mem}g" \
      GenotypeGVCFs \
      -R ${ref_seq} \
      -L $chr \
      -V ${gvcf} \
      -stand-call-conf ${call_conf} \
      -A Coverage -A FisherStrand -A StrandOddsRatio -A MappingQualityRankSumTest -A QualByDepth -A RMSMappingQuality -A ReadPosRankSumTest \
      --allow-old-rms-mapping-quality-annotation-data \
      -O "${params.cohort_id}.${chr}.vcf.gz"
      """
  }
}

if (db_import == "yes") {
  process run_genotype_gvcf_on_genome_db {
      tag { "${params.project_name}.${params.cohort_id}.${chr}.rGGoG" }
      memory { 48.GB * task.attempt }  
      publishDir "${params.out_dir}/${params.cohort_id}/exome-calling", mode: 'copy', overwrite: false
      label 'gatk'
    
      input:
      file ref_seq
      file ref_seq_index
      file ref_seq_dict
      file db
      each chr from chroms
  
      output:
      set chr, file("${params.cohort_id}.${chr}.vcf.gz"), file("${params.cohort_id}.${chr}.vcf.gz.tbi") into gg_vcf_set
      file("${params.cohort_id}.${chr}.vcf.gz") into gg_vcf
  
      script:
        mem = task.memory.toGiga() - 16
        call_conf = 30 // set default
        if ( params.sample_coverage == "high" )
          call_conf = 30
        else if ( params.sample_coverage == "low" )
          call_conf = 10
      """
      gatk --java-options  "-XX:+UseSerialGC -Xms4g -Xmx${mem}g" \
      GenotypeGVCFs \
      -R ${ref_seq} \
      -L $chr \
      -V gendb://${db}/${chr}.gdb \
      -stand-call-conf ${call_conf} \
      -A Coverage -A FisherStrand -A StrandOddsRatio -A MappingQualityRankSumTest -A QualByDepth -A RMSMappingQuality -A ReadPosRankSumTest \
      --allow-old-rms-mapping-quality-annotation-data \
      -O "${params.cohort_id}.${chr}.vcf.gz"
      """
  }
}

gg_vcf.toList().set{ concat_ready  }

if (params.build == "b37") {
  process run_concat_vcf_build37 {
       tag { "${params.project_name}.${params.cohort_id}.rCV" }
       memory { 16.GB * task.attempt }  
       publishDir "${params.out_dir}/${params.cohort_id}/exome-calling", mode: 'copy', overwrite: false
       label 'gatk'
  
       input:
       file(vcf) from concat_ready
  
       output:
  	   set file("${params.cohort_id}.vcf.gz"), file("${params.cohort_id}.vcf.gz.tbi") into combined_calls
  
       script:
         mem = task.memory.toGiga() - 4
       """
       echo "${vcf.join('\n')}" | grep "\\.1\\.vcf.gz" > ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.2\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.3\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.4\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.5\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.6\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.7\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.8\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.9\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.10\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.11\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.12\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.13\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.14\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.15\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.16\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.17\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.18\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.19\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.20\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.21\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.22\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.X\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.Y\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.MT\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       
       gatk --java-options  "-XX:+UseSerialGC -Xms4g -Xmx${mem}g" \
       GatherVcfs \
       -I ${params.cohort_id}.vcf.list \
       -O ${params.cohort_id}.vcf.gz # GatherVCF does not index the VCF. The VCF will be indexed in the next tabix operation.
       tabix -p vcf ${params.cohort_id}.vcf.gz
       """
  }
}

if (params.build == "b38") {
  process run_concat_vcf_build38 {
       tag { "${params.project_name}.${params.cohort_id}.rCV" }
       memory { 16.GB * task.attempt }  
       publishDir "${params.out_dir}/${params.cohort_id}/exome-calling", mode: 'copy', overwrite: false
       label 'gatk'
  
       input:
       file(vcf) from concat_ready
  
       output:
  	   set file("${params.cohort_id}.vcf.gz"), file("${params.cohort_id}.vcf.gz.tbi") into combined_calls
  
       script:
         mem = task.memory.toGiga() - 4
       """
       echo "${vcf.join('\n')}" | grep "\\.chr1\\.vcf.gz" > ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr2\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr3\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr4\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr5\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr6\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr7\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr8\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr9\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr10\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr11\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr12\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr13\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr14\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr15\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr16\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr17\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr18\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr19\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr20\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr21\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chr22\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chrX\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chrY\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       echo "${vcf.join('\n')}" | grep "\\.chrM\\.vcf.gz" >> ${params.cohort_id}.vcf.list
       
       gatk --java-options  "-XX:+UseSerialGC -Xms4g -Xmx${mem}g" \
       GatherVcfs \
       -I ${params.cohort_id}.vcf.list \
       -O ${params.cohort_id}.vcf.gz # GatherVCF does not index the VCF. The VCF will be indexed in the next tabix operation.
       tabix -p vcf ${params.cohort_id}.vcf.gz
       """
  }
}

process run_select_snps {
    tag { "${params.project_name}.${params.cohort_id}.rsS" }
    memory { 8.GB * task.attempt }  
    publishDir "${params.out_dir}/${params.cohort_id}/exome-calling", mode: 'copy', overwrite: false
    label 'gatk'
    
    input:
    set file(vcf), file(vcf_index) from combined_calls
    file ref_seq
    file ref_seq_index
    file ref_seq_dict
 
    output:
    set file("${params.cohort_id}.SNPs.vcf.gz"), file("${params.cohort_id}.SNPs.vcf.gz.tbi") into snps

    script:
       mem = task.memory.toGiga() - 4
    """
    gatk --java-options  "-XX:+UseSerialGC -Xms4g -Xmx${mem}g" \
    SelectVariants \
   -R ${ref_seq} \
   -select-type SNP \
   -V ${vcf} \
   -O "${params.cohort_id}.SNPs.vcf.gz" \
   """
}

process run_select_indels {
    tag { "${params.project_name}.${params.cohort_id}.rsI" }
    memory { 8.GB * task.attempt }  
    publishDir "${params.out_dir}/${params.cohort_id}/exome-calling", mode: 'copy', overwrite: false
    label 'gatk'
    
    input:
    set file(vcf), file(vcf_index) from combined_calls
    file ref_seq
    file ref_seq_index
    file ref_seq_dict
 
    output:
    set file("${params.cohort_id}.INDELs.vcf.gz"), file("${params.cohort_id}.INDELs.vcf.gz.tbi") into indels

    script:
       mem = task.memory.toGiga() - 4
    """
    gatk --java-options  "-XX:+UseSerialGC -Xms4g -Xmx${mem}g" \
    SelectVariants \
   -R ${ref_seq} \
   -select-type INDEL \
   -V ${vcf} \
   -O "${params.cohort_id}.INDELs.vcf.gz" \
   """
}

process run_filter_snps {
    tag { "${params.project_name}.${params.cohort_id}.rfS" }
    memory { 8.GB * task.attempt }  
    publishDir "${params.out_dir}/${params.cohort_id}/exome-calling", mode: 'copy', overwrite: false
    label 'gatk'
    
    input:
    set file(vcf), file(vcf_index) from snps
    file ref_seq
    file ref_seq_index
    file ref_seq_dict
 
    output:
    set file("${params.cohort_id}.SNPs.filtered.vcf.gz"), file("${params.cohort_id}.SNPs.filtered.vcf.gz.tbi") into snps_filtered

    script:
       mem = task.memory.toGiga() - 4
    """
    gatk --java-options  "-XX:+UseSerialGC -Xms4g -Xmx${mem}g" \
    VariantFiltration \
   -R ${ref_seq} \
   --filter-expression "QD < 2.0" --filter-name "QD_lt_2" \
   --filter-expression "FS > 60.0" --filter-name "FS_gt_60" \
   --filter-expression "MQ < 40.0" --filter-name "MQ_lt_40" \
   --filter-expression "MQRankSum < -12.5" --filter-name "MQRS_lt_n12.5" \
   --filter-expression "ReadPosRankSum < -8.0" --filter-name "RPRS_lt_n8" \
   --filter-expression "SOR > 3.0" --filter-name "SOR_gt_3" \
   -V ${vcf} \
   -O "${params.cohort_id}.SNPs.filtered.vcf.gz" \
   """
}

process run_filter_indels {
    tag { "${params.project_name}.${params.cohort_id}.rfI" }
    memory { 8.GB * task.attempt }  
    publishDir "${params.out_dir}/${params.cohort_id}/exome-calling", mode: 'copy', overwrite: false
    label 'gatk'
    
    input:
    set file(vcf), file(vcf_index) from snps
    file ref_seq
    file ref_seq_index
    file ref_seq_dict
 
    output:
    set file("${params.cohort_id}.INDELs.filtered.vcf.gz"), file("${params.cohort_id}.INDELs.filtered.vcf.gz.tbi") into indels_filtered

    script:
       mem = task.memory.toGiga() - 4
    """
    gatk --java-options  "-XX:+UseSerialGC -Xms4g -Xmx${mem}g" \
    VariantFiltration \
   -R ${ref_seq} \
   --filter-expression "QD < 2.0" --filter-name "QD_lt_2" \
   --filter-expression "FS > 200.0" --filter-name "FS_gt_200" \
   --filter-expression "ReadPosRankSum < -20.0" --filter-name "RPRS_lt_n20" \
   --filter-expression "SOR > 10.0" --filter-name "SOR_gt_10" \
    -V ${vcf} \
   -O "${params.cohort_id}.INDELs.filtered.vcf.gz" \
   """
}

process run_merge_snps_indels {
    tag { "${params.project_name}.${params.cohort_id}.rmSI" }
    memory { 8.GB * task.attempt }  
    publishDir "${params.out_dir}/${params.cohort_id}/exome-calling", mode: 'copy', overwrite: false
    label 'gatk'
    
    input:
    set file(vcf_s), file(vcf_s_index) from snps_filtered
    set file(vcf_i), file(vcf_i_index) from indels_filtered
    file ref_seq
    file ref_seq_index
    file ref_seq_dict
 
    output:
    set file("${params.cohort_id}.filtered.vcf.gz"), file("${params.cohort_id}.filtered.vcf.gz.tbi") into filtered

    script:
       mem = task.memory.toGiga() - 4
    """
    gatk --java-options  "-XX:+UseSerialGC -Xms4g -Xmx${mem}g" \
    MergeVcfs \
   -R ${ref_seq} \
   -I ${vcf_s} \
   -I ${vcf_i} \
   -O "${params.cohort_id}.filtered.vcf.gz" \
   """
}

process run_select_pass {
    tag { "${params.project_name}.${params.cohort_id}.rsP" }
    memory { 8.GB * task.attempt }  
    publishDir "${params.out_dir}/${params.cohort_id}/exome-calling", mode: 'copy', overwrite: false
    label 'gatk'
    
    input:
    set file(vcf), file(vcf_index) from filtered
    file ref_seq
    file ref_seq_index
    file ref_seq_dict
 
    output:
    set file("${params.cohort_id}.filtered.pass.vcf.gz"), file("${params.cohort_id}.filtered.pass.vcf.gz.tbi") into pass

    script:
       mem = task.memory.toGiga() - 4
    """
    gatk --java-options  "-XX:+UseSerialGC -Xms4g -Xmx${mem}g" \
    SelectVariants \
   -R ${ref_seq} \
   --exclude-filtered \
   -V ${vcf} \
   -O "${params.cohort_id}.filtered.pass.vcf.gz" \
   """
}

workflow.onComplete {

    println ( workflow.success ? """
        Pipeline execution summary
        ---------------------------
        Completed at: ${workflow.complete}
        Duration    : ${workflow.duration}
        Success     : ${workflow.success}
        workDir     : ${workflow.workDir}
        exit status : ${workflow.exitStatus}
        """ : """
        Failed: ${workflow.errorReport}
        exit status : ${workflow.exitStatus}
        """
    )
}
