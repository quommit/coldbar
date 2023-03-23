#!/bin/bash
# coldbar: Locate low-temperature land areas using NetCDF data and PostgreSQL
# This is the source code for coldbar's command
# line interface (CLI). The CLI consists of a single
# command (coldbar) that may be followed by one
# subcommand. Subcommands perform operations that
# involve reading NetCDF metadata, writing NetCDF
# datasets to PostgreSQL and computing statistics.

# The errtrace option is set in order to propagate error
# trapping through functions, command substitutions and
# subshells.
set -o errtrace
# Set the trap function which enables error trapping
# when a command exits with non-zero status.
trap 'raiseerror' ERR

# Remove temporary directories in /data on script EXIT
trap "rm -rf /data/tmp.*" EXIT

readonly PGTAP_FILE=/usr/local/bin/coldbar/tap.sql
ERR_SOURCE=main_context

# Trap function for ERR signals. This function is meant
# to handle errors originating in coldbar's functions
# where the $ERR_SOURCE global variable has been set.
# The convention is to assign the function name to the
# $ERR_SOURCE variable, although its value is never
# checked. The three step logic for error handling is:
#  1) Test whether $ERR_SOURCE is set.
#  2) If this is the case, print the error location
#     to STDERR using BASH internal variables.
#  3) Unset $ERR_SOURCE to ignore following items
#     in the error trace.
# This way only the innermost error is retrieved.
# Shall the $ERR_SOURCE variable not be unset, then
# this function should be modified to handle the
# complete error trace.
raiseerror() {
    [[ -z ${ERR_SOURCE} ]] \
	|| printf "The following command failed: %s \nSource: function %s in %s at line %s\n" \
		  "${BASH_COMMAND}" ${FUNCNAME[1]} ${BASH_SOURCE[1]} ${BASH_LINENO} \
	    && unset ERR_SOURCE
}

# @describe coldbar: Locate low-temperature land areas using NFC data and PostgreSQL

# @version 0.1

# @author Jose Tomas Navarro Carrion <jt.navarro@ua.es>

# @cmd  Print dimensions and variables in the input NetCDF file
# @flag -t --tar        Read first NetCDF in input tar archive
# @arg  source!         Input NetCDF filename (or tar archive if --tar is given)
explain() {
    local filename
    filename=$(realpath -e ${argc_source})
    if [[ -z ${argc_tar} ]]; then
	ncks -m ${filename}
    else
	local nc_filename
	nc_filename=$(tar -tf ${filename} --wildcards "*.nc" | head -n 1)
	pushd $(mktemp -d -p /data)
	tar -xvf ${filename} ${nc_filename}
	ncks -m ${nc_filename}
	popd
    fi
}

configure_from() {
    local cfg_filename
    cfg_filename=$1
    local -n cfgref
    cfgref=$2
    while read -r k v; do
	cfgref["$k"]="$v"
    done < $cfg_filename
}

configure() {
    local filename
    filename=$1
    # Convert all characters in varname string to lower case.
    local -l varname
    varname=$2
    local nc_varname
    # Let awk find the minimum temperature variable name.
    # Notice the use of tolower() function in order to
    # apply a case insensitive search.
    nc_varname=$(ncks --trd -m $filename | awk -v search="^${varname}: type" 'tolower($0) ~ search {sub(/:$/, "", $1); print $1}')
    # Get number of dimensions of the minimum tamperature variable
    local -n cfgref
    cfgref=$3
    # Get dimensions of the minimum temperature variable
    local dims
    dims=$(ncks --trd -m -v $nc_varname $filename | awk -v search="^${nc_varname} dimension" '$0 ~ search {sub(/,$/, "", $4); print $3 $4}')
    cfgref[varname]=$nc_varname
    cfgref[varpos]=$(ncks --trd -m -v $nc_varname $filename | awk -v search="^${nc_varname}.+dimensions" '$0 ~ search {print $4}')
    cfgref[t1]=$(ncks --trd -m $filename | awk -F " days since " '/ days since / {print $2}') 
    cfgref[tpos]=$(echo "$dims" | awk -F ":" 'tolower($2) ~ /time/ {print $1; exit}')
    cfgref[tsize]=$(ncks --trd -m $filename | awk 'tolower($0) ~ /^time dimension/ {print $7; exit}')
    cfgref[xpos]=$(echo "$dims" | awk -F ":" 'tolower($2) ~ /lon/ {print $1; exit}')
    cfgref[ypos]=$(echo "$dims" | awk -F ":" 'tolower($2) ~ /lat/ {print $1; exit}')
    cfgref[missing]=$(ncks --trd -m -v $nc_varname $filename | awk -v search="^${nc_varname} attribute.+missing_value" '$0 ~ search {print $NF}')
}

configure_lonlat() {
    local filename
    filename=$1
    local -n cfgref
    cfgref=$2
    cfgref[longitude]=$(ncks --trd -m $filename | awk -F ":" 'tolower($0) ~ /lon.+2 dimensions/ {print $1}')
    cfgref[latitude]=$(ncks --trd -m $filename | awk -F ":" 'tolower($0) ~ /lat.+2 dimensions/ {print $1}')
}

dump_lonlat() {
    local nc_filename
    nc_filename=$1
    local -n cfgref
    cfgref=$2
    # Get longitude and latitude columns, then paste them and concatenate n times
    # where n is the size of the time dimension (i.e. number of days in a year)
    ncks --trd -H -C -v ${cfgref["longitude"]} ${nc_filename} | awk -F "=" '{$NF=$NF};NF' | awk '{print $NF}' > lon
    ncks --trd -H -C -v ${cfgref["latitude"]} ${nc_filename} | awk -F "=" '{$NF=$NF};NF' | awk '{print $NF}' > lat
    for ((i=0;i<${cfgref["tsize"]};i++)); do paste -d "," lon lat >> lonlat; done
}

dump() (
    local nc_filename
    nc_filename=$1
    local -n cfgref
    cfgref=$2
    local t
    let t=(${cfgref[tpos]}+1)*2
    local x
    let x=(${cfgref[xpos]}+1)*2
    local y
    let y=(${cfgref[ypos]}+1)*2
    local v
    let v=(${cfgref[varpos]}+1)*2
    local trd_filename
    trd_filename=$(basename ${nc_filename} ".nc")".trd"
    # Write temperature records to a text file in tabular format
    ncks --trd -H -C -v ${cfgref["varname"]} ${nc_filename} > ${trd_filename}
    local csv_filename
    csv_filename=$(basename ${nc_filename} ".nc")".csv"
    awk -F "=" '{$NF=$NF};NF' ${trd_filename} | awk -v OFS="," -v t=${t} -v x=${x} -v y=${y} -v v=${v} '{print $t, $x, $y, $v}' > ${csv_filename}
    [[ -f lonlat && -s lonlat ]] && paste -d "," ${csv_filename} lonlat | awk -F "," -v OFS="," '{print $1, $5, $6, $4}'> cmb && mv cmb ${csv_filename}
    tail ${csv_filename}
)

# @cmd Write NetCDF temperature data to a PostgreSQL COPY file
# @flag    -t --tar         Input file is tar archive that contains NetCDF files
# @flag    -r --rotated     Longitude and latitude dimensions refer to a rotated pole grid
# @option  -c --cfg <PATH>  Use configuration file
# @option  -v --varname     Name of the variable that holds minimum temperature values
# @arg     source!          Input NetCDF filename (or tar archive if --tar is given)
# @arg     destination!     Output COPY filename
build() {
    if [[ -z ${argc_cfg} && -z ${argc_varname} ]]; then
	echo "Provide one of the following options:"
	echo "  --cfg <path_to_configuration_file>"
	echo "  --varname <minimum_temperature_variable_name>"
	echo "The minimum temperature varname option will be ignored, in case both are provided."
	return
    fi
    local filename
    filename=$(realpath -e ${argc_source})
    local nc_filename
    local -A cfg
    # Load configuration from file given in --cfg option
    if [[ -n ${argc_cfg} ]]; then
	local cfg_filename
	cfg_filename=$(realpath -e ${argc_cfg})
	configure_from $cfg_filename cfg
    # Or configure automatically when no configuration file is given and --varname is provided
    else
	if [[ -z ${argc_tar} ]]; then
	    nc_filename=${filename}
	else
	    nc_filename=$(tar -tf ${filename} --wildcards "*.nc" | head -n 1)
	    pushd $(mktemp -d -p /data)
	    tar -xvf ${filename} ${nc_filename}
	fi
	configure ${nc_filename} ${argc_varname} cfg
	if [[ -n ${argc_rotated} ]]; then
	    configure_lonlat ${nc_filename} cfg
	fi
	# Change to the top directory if the directory stack is not empty
	[[ $(dirs -v | wc -l) != "1" ]] && popd > /dev/null
    fi
    declare -p cfg
    pushd $(mktemp -d -p /data)
    if [[ -z ${argc_tar} ]]; then
	nc_filename=${filename}
	[[ ${cfg["latitude"]} ]] && dump_lonlat ${nc_filename} cfg
	dump ${nc_filename} cfg
    else
	tar -tf ${filename} --wildcards "*.nc" > ncfiles
	#TODO: dump in parallel
    fi
    popd
}

eval $(argc "$0" "$@")
