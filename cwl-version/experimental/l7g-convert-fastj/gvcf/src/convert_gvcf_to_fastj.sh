#!/bin/bash

set -a

DEBUG=0
export MAKE_NEW_DIR=1
export VERBOSE=1

function _q {
  echo $1
  exit 1
}

gvcf="$1"
tagset="$2"
afn="$3"
reffa="$4"
ref="$5"
out_name="$6"

if [[ "$gvcf" == "" ]] ; then
  echo "provide gvcf file"
  exit 1
fi

if [ "$tagset" == "" ] || [ "$afn" == "" ] || [ "$reffa" == "" ] ; then
  echo "provide tagset, tile assembly and FASTA reference"
  exit 1
fi

export aidx="$afn.fwi"

if [ "$ref" == "" ] ; then
  #export ref='hg19'
  ref=`basename $reffa .gz`
  ref=`basename $ref .fa`
  ref=`basename $ref .fasta`
fi

if [[ "$out_name" == "" ]] ; then
  out_name=`basename $gff .gz`
  out_name=`basename $out_name .gff`
fi


if [[ "$VERBOSE" -eq 1 ]] ; then
  echo "individual variable listings"
  echo "gvcf $gvcf"
  echo "tagset $tagset"
  echo "afn $afn"
  echo "reffa $reffa"
  echo "ref $ref"
  echo "out_name $out_name"
fi

mkdir -p $out_name
export odir="$out_name"

for chrom in chr1 chr2 chr3 chr4 chr5 chr6 chr7 chr8 chr9 chr10 chr11 chr12 chr13 chr14 chr15 chr16 chr17 chr18 chr19 chr20 chr21 chr22 chrX chrY chrM ; do
#for chrom in chr22 chrM ; do

  if [[ "$VERBOSE" -eq 1 ]] ; then
    echo "## chrom $chrom"
  fi

  refchrom="$chrom"
  if [[ "$ref" == "human_g1k_v37" ]] ; then
    refchrom=`echo "$chrom" | sed 's/^chr//'`
    if [[ "$refchrom" == "M" ]] ; then
      refchrom="MT"
    fi
  fi

  if [[ "$VERBOSE" -eq 1 ]] ; then
    echo "## refchrom $refchrom"
  fi

  while read line
  do

    tilepath=`echo "$line" | cut -f1 | cut -f3 -d':'`

    if [[ "$VERBOSE" -eq 1 ]] ; then
      echo "tilepath $tilepath"
    fi

    ## Due to technical limitations, we can't convert from gVCF in the middle
    ## of a gVCF line.
    ## If the first gVCF line starts after the start of the tile path, use the tilepath start
    ##   as the beginning point.
    ## If the beginning of the tile path starts in the middle of the gVCF line, start at
    ## the beginning of the gVCF line.
    ##
    ## The ending gVCF line has similar complications.
    ## If the last gVCF line ends before end of the tilepath, use the end of the tilepath
    ## If the end of the tilepath falls in the middle of the last gVCF line, use the ending
    ##   of the gVCF line as the end.
    ## Care has to be taken as the gVCF can have an 'END' filed which has the end of the
    ##   block in question.
    ## If the 'END' field isn't present, but the reference sequence is greater than 1, the
    ##   length of the reference sequence is taken as the length of the block.
    ##
    ## "window_start" is where the final start of the window for filtering the gVCF is stored
    ## "window_len" is the window length
    ## "tilepath_start0" is the start of the tilepath
    ## "tilepath_len" is the length of the tilepath
    ##
    ## The larger window is converted from gVCF to PASTA and is then filtered down
    ## to the proper tilepath length.
    ##
    ##  [window_start     ....         +window_len)
    ##   [tilepath_start0 .... +tilepath_len]
    ##

    ## find the bounds for the tilepath
    ##
    export tilepath_start0=`tile-assembly range $afn $tilepath | tail -n1 | cut -f2`
    export tilepath_end0_noninc=`tile-assembly range $afn $tilepath | tail -n1 | cut -f3`
    export tilepath_len=`expr "$tilepath_end0_noninc" - "$tilepath_start0"` || true

    if [[ "$tilepath_len" -eq "0" ]] ; then
      echo "SKIPPING EMPTY TILEPATH $tilepath (tilepath_len: $tilepath_len)"
      continue
    fi

    if [[ "$VERBOSE" -eq 1 ]] ; then
      echo "## tilepath reference start0 $tilepath_start0"
      echo "## tilepath len $tilepath_len"
    fi

    export tilepath_start1=`expr "$tilepath_start0" + 1` || true
    export tilepath_end1_inc=`expr "$tilepath_start0" + "$tilepath_len" + 1` || true

    ## find the bounds for gvcf snippet in question
    ##
    export gvcf_start1=`tabix $gvcf $chrom:$tilepath_start1-$tilepath_end1_inc | head -n1 | cut -f2`
    export gvcf_end1_inc=`tabix $gvcf $chrom:$tilepath_start1-$tilepath_end1_inc | tail -n1 | cut -f2`

    export gvcf_start0="$tilepath_start0"
    if [[ "$gvcf_start1" != "" ]] ; then
      gvcf_start0=`expr "$gvcf_start1" - 1` || true
    fi

    gvcf_tok_end1_inc=`tabix $gvcf $chrom:$tilepath_start1-$tilepath_end1_inc | grep END | tail -n1 | cut -f8 | cut -f2 -d'='`
    if [[ "$gvcf_tok_end1_inc" != "" ]] && [[ "$gvcf_tok_end1_inc" -gt "$gvf_end1_inc" ]] ; then
      gvcf_end1_inc="$gvcf_tok_end1_inc"
    fi

    ## The window under consideration starts at the minimum
    ## of the tilepath start and the gvcf start
    ##
    export window_start0="$tilepath_start0"
    if [[ "$gvcf_start0" -lt "$window_start0" ]] ; then
      window_start0="$gvcf_start0"
    fi
    export window_start1=`expr "$window_start0" + 1` || true

    ## now find the end of the window by taking the maximum
    ## of the tilepath end, the last gvcf reported position
    ##

    export window_end1_inc="$tilepath_end0_noninc"
    if [[ "$gvcf_end1_inc" != "" ]] && [[ "$gvcf_end1_inc" -gt "$window_end1_inc" ]] ; then
      window_end1_inc="$gvcf_end1_inc"
    fi

    ## take the maximum of the 'END' field or the length of the reference sequence
    ## in the 'REF' column.
    ##
    fin_ent_len=`tabix $gvcf $chrom:$tilepath_start1-$tilepath_end1_inc | tail -n1 | cut -f4 | tr -d '\n' | wc -c`
    fin_ent_start1=`tabix $gvcf $chrom:$tilepath_start1-$tilepath_end1_inc | tail -n1 | cut -f2 | tr -d '\n' `
    fin_ent_end1_inc=`expr $fin_ent_start1 + $fin_ent_len - 1` || true

    if [[ "$fin_ent_end1_inc" != "" ]] && [[ "$fin_ent_end1_inc" -gt "$window_end1_inc" ]] ; then
      window_end1_inc="$fin_ent_end1_inc"
    fi

    if [[ "$window_start1" -gt "$window_end1_inc" ]] ; then
      echo "SKIPPING EMPTY TILEPATH $tilepath (window: $window_start1-$window_end1_inc)"
      continue
    fi

    export window_len=`expr "$window_end1_inc" "-" "$window_start1" + 1` || true

    ## I'm getting segfaults from what I think are truncated streams.  I think the issue
    ## is tabix for some reason prematurely terminating the stream.
    ## To try and mitigate this, write to a temporary file then delete afterwards
    ##
    tdir=`mktemp -d`

    if [[ "$VERBOSE" -eq 1 ]] ; then

      echo "##"
      echo "## window_start0: $window_start0"
      echo "## window_start1: $window_start1"
      echo "## window_end1_inc: $window_end1_inc"
      echo "## window_len: $window_len"
      echo "##"

      echo "## tilepath_start0: $tilepath_start0"
      echo "## tilepath_start1: $tilepath_start1"
      echo "## tilepath_end0_noninc: $tilepath_end0_noninc"
      echo "## tilepath_end_inc: $tilepath_end1_inc"
      echo "## tilepath_len $tilepath_len"
      echo "##"

      echo "## gvcf_start0: $gvcf_start0"
      echo "## gvcf_start1: $gvcf_start1"
      echo "## gvcf_end1_inc: $gvcf_end1_inc"
      echo "## gvcf_tok_end1_inc $gvcf_tok_end1_inc"
      echo "##"

      echo "## fin_ent_len: $fin_ent_len"
      echo "## fin_ent_start1: $fin_ent_start1"
      echo "## fin_ent_end1_inc: $fin_ent_end1_inc"
      echo "##"

      echo "## TDIR: $tdir"
    fi

    if [[ "$VERBOSE" -eq 1 ]] ; then
      echo "refstream $reffa "$refchrom:$window_start1+$window_len" > $tdir/$tilepath.ref"
      echo "cat <( echo -e '\n\n\n' ) <( tabix $gvcf $chrom:$window_start1-$window_end1_inc ) > $tdir/$tilepath.gvcf"
    fi

    refstream $reffa "$refchrom:$window_start1+$window_len" > $tdir/$tilepath.ref
    cat <( echo -e '\n\n\n' ) <( tabix $gvcf $chrom:$window_start1-$window_end1_inc ) > $tdir/$tilepath.gvcf

    if [[ "$VERBOSE" -eq 1 ]] ; then
      echo "pasta -action gvcf-rotini -start $window_start0 -chrom $chrom \
        -refstream $tdir/$tilepath.ref \
        -i $tdir/$tilepath.gvcf | \
        pasta -action filter-rotini -start $tilepath_start0 -n $tilepath_len > $odir/$tilepath.pa"
    fi

    pasta -action gvcf-rotini -start $window_start0 -chrom $chrom \
      -full-sequence \
      -refstream $tdir/$tilepath.ref \
      -i $tdir/$tilepath.gvcf | \
      pasta -action filter-rotini -start $tilepath_start0 -n $tilepath_len > $odir/$tilepath.pa

    ## clean up gvcf and ref temporary files
    ##
    rm -rf $tdir

    if [[ "$VERBOSE" -eq 1 ]] ; then
      echo "pasta -action rotini-fastj -start $tilepath_start0 -tilepath $tilepath -chrom $chrom -build $ref \
        -i $odir/$tilepath.pa \
        -assembly <( tile-assembly tilepath $afn $tilepath ) \
        -tag <( cat <( samtools faidx $tagset $tilepath.00 | egrep -v '^>' | tr -d '\n' | fold -w 24 ) <(echo ) ) > $odir/$tilepath.fj"
    fi

    pasta -action rotini-fastj -start $tilepath_start0 -tilepath $tilepath -chrom $chrom -build $ref \
      -i $odir/$tilepath.pa \
      -assembly <( tile-assembly tilepath $afn $tilepath ) \
      -tag <( cat <( samtools faidx $tagset $tilepath.00 | egrep -v '^>' | tr -d '\n' | fold -w 24 ) <( echo )  ) > $odir/$tilepath.fj

    rm -f $odir/$tilepath.pa
    bgzip -f $odir/$tilepath.fj
    bgzip -r $odir/$tilepath.fj.gz

  done < <( egrep '^'$ref':'$refchrom':' $aidx )

done # chrom
