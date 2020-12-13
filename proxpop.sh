#!/bin/bash
# ProxPop v0: A simple bash script that populates the proxychains config (/etc/proxychains.conf) with proxies from custom resources.
# Written by verghost (https://github.com/verghost)

usage=\
'ProxPop: Proxychains config populator
A simple bash script that populates the proxychains config (/etc/proxychains.conf) with proxies from custom resources.

usage: proxpop.sh [options]
	[Proxy Types]
	--only-http    Populate only HTTP proxies
	--only-socks4  Populate only SOCKS4 proxies
	--only-socks5  Populate only SCOKS5 proxies
	
	[Template Options]
	-t, --template Use custom template file (Default is proxychains.template)
	-c, --chain    Specify a custom chain file (ex. proxpop.sh ... -c chain.txt)
	-r, --resource Specify a custom resource file (ex. proxpop.sh ... -r resource.txt)
	-q, --quiet    Use proxychains quiet mode
	--no-proxy-dns Do NOT proxy DNS requests (this is ON by default)
	--use-strict   Use strict chain in template file (default is dynamic_chain)
	--use-random   Use random chain. You can optionally provide chain length: proxpop.sh ... --use-random 3 (Default length is: 2)
	
	[Saftey Options]
	-o, --output   Choose an output location for the new config file (Default is /etc/proxychains.conf)
	-k, --keep     Keep old configuration file (Old file is copied to /usr/share/proxpop/proxychains.old)
	--restore      Restore the old configuration file (this does not run proxpop)
	--review       Review final configuration file before finalizing (--silent does not apply to this option)
	
	[Fetch Options]
	--tor-fetch    Try to fetch resources through TOR (must have TOR installed, may not work since many sites block TOR nodes)
	--proxy-fetch  Try to fetch resources through proxy (may not work if proxychains is improperly configured)
	
	[Other Options]
	-s, --silent   Do not display output (does not apply to --review, torify or proxychains)
	-h, --help     Show this message
'

TEMPLATE_MODE="dynamic_chain"
#TEMPLATE_TORLINE="socks4 127.0.0.1 9050"

declare -A PP_TOPTS # template options
PP_TOPTS["quiet_mode"]="#" # this indicates that we will comment out this option
PP_TOPTS["proxy_dns"]=""
PP_TOPTS["chain_len"]="#"
PP_TOPTS["tcp_read_time_out"]=15000
PP_TOPTS["tcp_connect_time_out"]=8000

PROXPOP_HTTP=1; PROXPOP_SOCKS4=1; PROXPOP_SOCKS5=1;

TMP_HTTP="/tmp/http_prox"
TMP_SOCKS4="/tmp/socks5_prox"
TMP_SOCKS5="/tmp/socks4_prox"
TMP_CONF="/tmp/proxychains_${RANDOM}.conf"

PROXPOP_OUTPUT="/etc/proxychains.conf"
OLD_CONFIG="/usr/share/proxpop/proxychains.old"

CHAIN_FILE=""
RESOURCE_FILE="/usr/share/proxpop/resources.default" # Defaults
TEMPLATE_FILE="/usr/share/proxpop/proxychain.template"


# Util functions
pp_yorn() {
	while true; do
		echo -n "$1 (y/N): "
		read -r yorn
		if [[ "$yorn" == "y" ]] || [[ "$yorn" == "Y" ]]; then PP_YORN_RET="y"; break
		elif [[ "$yorn" == "n" ]] || [[ "$yorn" == "N" ]]; then PP_YORN_RET="n"; break
		else echo "Not a valid response!"; fi
	done
}

# Check for natural number (defined for our purposes as an integer >=0)
pp_isnat() {
	case "$1" in # https://stackoverflow.com/a/3951175
		''|*[!0-9]*) ;; # negates strings, floating point and negative numbers
		*) echo 1 ;;
	esac
}

pp_echo() {
	if [[ ! $PROXPOP_SILENT ]]; then echo "$*"; fi
}

pp_error() {
	local code=$2; [[ "$code" == "" ]] && code=1;
	echo "$1" >&2
	exit "$code"
}

pp_exit() {
	echo "Cleaning up..."
	rm -f $TMP_CONF
	rm -f $TMP_HTTP $TMP_SOCKS4 $TMP_SOCKS5
	
	echo "| -------- |"
	echo "| ALL DONE |"
	echo "| -------- |"
	
	exit "$1"
}

pp_curl() {
	local out=$1; shift
	local tmpf="./.tmpfile_${RANDOM}"
	if [[ $PROXPOP_TORFETCH ]]; then 
		torify curl -s -o $tmpf "$@"
	elif [[ $PROXPOP_PROXYFETCH ]]; then
		proxychains curl -s -o $tmpf "$@"
	else
		curl -s -o $tmpf "$@"
	fi
	cat $tmpf >> "$out"
	rm -f $tmpf
}

set_template_mode() {
	# is this still the default?
	if [[ "$TEMPLATE_MODE" == "dynamic_chain" ]]; then TEMPLATE_MODE="$1"
	else pp_error "You must only specify one mode!"; fi
}

get_file() {
	if [[ -f $1 ]]; then echo "$1"; shift
	else pp_error "$1 is not a file!"; fi
}

get_first_n() {
	if [[ $(pp_isnat "$1") ]]; then echo "$1"
	else echo "$2"; fi # default value
}

# ProxPop main code

add_proxy() {
	local type=$1 file=$2 n=$3 i=0
	while IFS= read -r ipp; do
		if [[ ! "$n" == "" ]] && [[ $i -ge $n ]]; then break; fi
		echo "$type $ipp" | awk -F':' '{print $1,$2}' >> $TMP_CONF
		((i++))
	done < "$file"
	pp_echo "Added $i '${type}' proxies!"
}

add_proxies() {
	local type="" file="" rol=""
	if [[ -f $CHAIN_FILE ]]; then
		pp_echo "Parsing chain file..."
		while IFS= read -r line; do
			if [[ "${line:0:4}" == "http" ]]; then type="http"; file=$TMP_HTTP; rol="${line:5}"
			elif [[ "${line:0:6}" == "socks4" ]]; then type="socks4"; file=$TMP_SOCKS4; rol="${line:7}"
			elif [[ "${line:0:6}" == "socks5" ]]; then type="socks5"; file=$TMP_SOCKS5; rol="${line:7}"
			else continue; fi
			
			if [[ "$rol" == "rand" ]]; then
				pp_error "Not done yet!"
			elif [[ ! "$rol" == "" ]]; then
				if [[ $(pp_isnat "$rol") ]]; then add_proxy $type $file "$rol"
				else pp_error "Bad line in chain file: $line"; fi
			else add_proxy $type $file; fi
		done < "$CHAIN_FILE"
	else
		[[ $PROXPOP_HTTP ]] && add_proxy "http" $TMP_HTTP
		[[ $PROXPOP_SOCKS4 ]] && add_proxy "socks4" $TMP_SOCKS4
		[[ $PROXPOP_SOCKS5 ]] && add_proxy "socks5" $TMP_SOCKS5
	fi
}

populate() {
	pp_echo ""
	pp_echo "Starting ProxPop..."
	
	[[ $PROXPOP_KEEP ]] && cp -f $PROXPOP_OUTPUT $OLD_CONFIG # keep old config 
	
	pp_echo "Writing configuration file..."
	if [[ -f $TEMPLATE_FILE ]]; then
		cp -f $TEMPLATE_FILE $TMP_CONF
	else
		echo "" > $TMP_CONF # create empty config file
		echo "$TEMPLATE_MODE" > $TMP_CONF
		for k in "${!PP_TOPTS[@]}"; do
			if [[ ! "${PP_TOPTS[$k]:0:1}" == "#" ]]; then
				echo "$k ${PP_TOPTS[$k]}" >> $TMP_CONF
			fi
		done
	fi
	
	echo "[ProxyList]" >> $TMP_CONF # start proxy list in config
	
	pp_echo "Fetching proxies..."
	local prox_read=
	while IFS= read -r rec; do
		if [[ "${rec:0:4}" == "http" ]] && [[ $PROXPOP_HTTP ]]; then
			pp_curl $TMP_HTTP "${rec:5}"
			prox_read=1
		elif [[ "${rec:0:6}" == "socks4" ]] && [[ $PROXPOP_SOCKS4 ]]; then
			pp_curl $TMP_SOCKS4 "${rec:6}"
			prox_read=1
		elif [[ "${rec:0:6}" == "socks5" ]] && [[ $PROXPOP_SOCKS5 ]]; then
			pp_curl $TMP_SOCKS5 "${rec:6}"
			prox_read=1
		fi
	done < "$RESOURCE_FILE"
	
	if [[ ! $prox_read ]]; then
		pp_error "Error: No proxies to populate!"
	fi
	
	add_proxies
	
	sleep 1
	pp_echo "New configuration is ready!"
	
	if [[ $PROXPOP_REVIEW ]]; then
		sleep 1; echo "Please review the new file when it appears..."; sleep 2; more $TMP_CONF; echo ""
		pp_yorn "If this OK?" # start yorn
		if [[ "$PP_YORN_RET" == "y" ]]; then echo "OK, we got this!"
		else echo "OK, aborting..."; pp_exit 0; fi
	fi
	
	pp_echo "Writing final configuration..."
	chmod --reference=$PROXPOP_OUTPUT $TMP_CONF
	mv -f $TMP_CONF $PROXPOP_OUTPUT
	
	pp_exit 0
}

# Parse params
#declare -A PARAM_HISTORY
while [[ "$#" -gt 0 ]]; do
	case "$1" in
	# Proxy types
	--only-http) 
		shift
		PROXPOP_HTTP=1; PROXPOP_SOCKS4=; PROXPOP_SOCKS5=
	;;
	--only-socks4) 
		shift
		PROXPOP_HTTP=; PROXPOP_SOCKS4=1; PROXPOP_SOCKS5=
	;;
	--only-socks5) 
		shift
		PROXPOP_HTTP=; PROXPOP_SOCKS4=; PROXPOP_SOCKS5=1
	;;
	
	# Template options
	-t|--template) shift; TEMPLATE_FILE=$(get_file "$1") ;;
	-r|--resource) shift; RESOURCE_FILE=$(get_file "$1") ;;
	-c|--chain) 
		shift
		CHAIN_FILE=$(get_file "$1")
	;;
	-q|--quiet) PP_TOPTS["quiet_mode"]=""; shift; ;;
	--no-proxy-dns) PP_TOPTS["proxy_dns"]="#"; shift; ;;
	--use-strict) set_template_mode "strict_chain"; shift; ;;
	--use-random)
		set_template_mode "random_chain"
		shift
		PP_TOPTS["chain_len"]="= $(get_first_n "$1" d)"
		if [[ "${PP_TOPTS[chain_len]}" == "= d" ]]; then 
			PP_TOPTS["chain_len"]="= 2"
		else shift; fi
	;;
	
	# Safety options
	-o|--output)
		shift
		if [[ -f $1 ]]; then
			yorn "Wait! There is already a file at $1: do you want to overwrite it?"
			if [[ "$PP_YORN_RET" == "n" ]]; then
				echo "OK, aborting..."
				pp_exit 0
			fi
		fi
		PROXPOP_OUTPUT=$1; shift
	;;
	-k|--keep) PROXPOP_KEEP=1; shift; ;;
	--restore)
		if [[ -f $OLD_CONFIG ]]; then
			cp -f $OLD_CONFIG "$PROXPOP_OUTPUT"
			echo "Old configuration file was restored!"
			pp_exit 0
		else
			pp_error "No old configuration file was found!"
		fi
	;;
	--review) PROXPOP_REVIEW=1; shift; ;;
	
	# Fetch options
	--tor-fetch)
		if [[ $(command -v torify) ]]; then
			PROXPOP_TORFETCH=1
			shift
		else 
			pp_error "Torify is not installed!"
		fi
	;;
	--proxy-fetch) PROXPOP_PROXYFETCH=1; shift; ;;
	
	# Other Options
	-s|--silent) PROXPOP_SILENT=1; shift; ;;
	-h|--help) echo "$usage"; exit; ;;
	
	-*) # handle unknown
		pp_error "Unknown option: $1"
	;;
	
	*) # other stuff
		pp_error "I have no idea why you passed $1!"
	;;
	esac
done

if [ "$EUID" -ne 0 ]; then
	pp_error "Error: This script must be run with elevated privileges!"
elif [[ ! $(command -v curl) ]]; then
	pp_error "Error: You must have curl installed!"
elif [[ ! $(command -v proxychains) ]]; then
	pp_error "Error: You must have proxychains installed!"
elif [[ -f $RESOURCE_FILE ]]; then
	pp_error "Error: Resource file does not exist!"
else
	populate
fi
