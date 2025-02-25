$namespaces:
  arv: "http://arvados.org/cwl#"
  cwltool: "http://commonwl.org/cwltool#"
cwlVersion: v1.0
class: CommandLineTool
label: Merges new tile library into existing tile library
requirements:
  DockerRequirement:
    dockerPull: arvados/l7g
  ResourceRequirement:
    coresMin: 8
    ramMin: 32000
hints:
  arv:RuntimeConstraints:
    keep_cache: 20000
inputs:
  bashscript:
    type: File
    label: Master script to merge tile libraries
    default:
      class: File
      location: src/merge-tilelibCWL.sh
  srclib:
    type: Directory?
    label: Existing tile library directory
  newlib:
    type: Directory
    label: New tile library directory to be added
  mergetilelib:
    type: string
    label: Code that merges SGLF libraries
    default: "/usr/local/bin/merge-sglf"
outputs:
  mergedlib:
    type: Directory
    label: Directory of merged tile library
    outputBinding:
      glob: "."
baseCommand: bash
arguments:
  - $(inputs.bashscript)
  - prefix: "-s"
    valueFrom: $(inputs.srclib)
  - prefix: "-n"
    valueFrom: $(inputs.newlib)
  - "6"
  - $(inputs.mergetilelib)
