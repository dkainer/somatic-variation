#!/usr/bin/env bash
#bash clean_reads.sh -t THREADS -d DEST_DIRECTORY -k KMER_SIZE -f FILE_SUFFIX -s SEARCH_STRING -r REPLACE_STRING [-m MAX_MEMORY] [-c COVERAGE] READ_DIRECTORY 
USAGE="Usage: $0 [-t THREADS] [-d DEST_DIRECTORY] [-k KMER_SIZE] [-f FILE_SUFFIX] [-1 SEARCH_STRING] [-2 REPLACE_STRING] [-m MAX_MEMORY] [-c COVERAGE] -i READ_DIRECTORY/"

RCORRECTOR="run_rcorrector.pl"
LOAD_COUNTING="load-into-counting.py"
SLICE_BY_COV="slice-paired-reads-by-coverage.py"
THREADS=48
DEST_DIRECTORY=./cleaned_reads
KMER_SIZE=32
FILE_SUFFIX='.fastq' #pattern to find first set of reads
SEARCH_STRING='R1' #pattern for search/replace to find second set of reads
REPLACE_STRING='R2' #pattern for search/replace to substitute second set of reads
MAX_MEMORY=64e9 #max memory to be given to khmer
COVERAGE=40000 #max coverage tolerable  (see khmer slice-reads-by-coverage)
READ_DIRECTORY=""

while getopts :t:d:k:f:s:r:m:c:i:h opt; do
	case $opt in
		t)
			THREADS=$OPTARG
			;;
		d)
			DEST_DIRECTORY=$OPTARG
			;;
		k)
			KMER_SIZE=$OPTARG
			;;
		f)
			FILE_SUFFIX=$OPTARG
			;;
		1)
			SEARCH_STRING=$OPTARG
			;;
		2)
			REPLACE_STRING=$OPTARG
			;;
		m)
			MAX_MEMORY=$OPTARG
			;;
		c)
			COVERAGE=$OPTARG
			;;
		i)
			READ_DIRECTORY=$OPTARG
			;;
		h)
			echo $USAGE >&2
			exit 1
			;;
	    \?)
			echo "Invalid option: -$OPTARG" >&2
			exit 1
			;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			exit 1
			;;
	esac
done

shift $((OPTIND-1))

if [ $# -ne 0 ]; then
	echo $USAGE >&2
	exit 1
fi

if [ "$READ_DIRECTORY" == "" ]; then
	echo $USAGE >&2
	echo "Input directory required." >&2
	exit 1
fi

if [ ! -d $READ_DIRECTORY ] ; then
	echo $USAGE >&2
	echo "Invalid argument ${READ_DIRECTORY}: Not a directory or unreadable." >&2
	exit 1
fi

trap "rm -rf $TMPDIR" EXIT INT TERM HUP
trap "exit 1" ERR

CORR_SUFFIX=.cor${FILE_SUFFIX//.fastq/.fq}
mkdir -p $DEST_DIRECTORY
mkdir -p ${DEST_DIRECTORY}/corrected
mkdir -p ${DEST_DIRECTORY}/sliced

# Run Rcorrector with the script included in the program:
for F in $(find $READ_DIRECTORY -name "*$FILE_SUFFIX" -and -name "*$SEARCH_STRING*"); do
	$RCORRECTOR -1 $F -2 ${F/$SEARCH_STRING/$REPLACE_STRING} -k $KMER_SIZE -t $THREADS -od ${DEST_DIRECTORY}/corrected/
done

# Build a graph with khmer
$LOAD_COUNTING -ksize $KMER_SIZE -T $THREADS -M $MAX_MEMORY khmer_count.graph ${DEST_DIRECTORY}/corrected/*${FILE_SUFFIX}

# filter on $COVERAGE in parallel using $SLICE_BY_COV
parallel -j $THREADS 'F={}; G={/.}; \
$SLICE_BY_COV -M $COVERAGE khmer_count.graph $F ${F/$SEARCH_STRING/$REPLACE_STRING} \
${DEST_DIRECTORY}/sliced/${G}_sliced${CORR_SUFFIX} \
${DEST_DIRECTORY}/sliced/${G/$SEARCH_STRING/$REPLACE_STRING}_sliced${CORR_SUFFIX} \
${DEST_DIRECTORY}/sliced/${G/$SEARCH_STRING/}_singletons${CORR_SUFFIX}' \
::: $(find $DEST_DIRECTORY/corrected/ -name "*$CORR_SUFFIX" -and -name "*${SEARCH_STRING}*")

exit
