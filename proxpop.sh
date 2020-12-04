#!/bin/bash
# ProxPop v0: A simple bash script that populates the proxychains config (/etc/proxychains.conf) with proxies from custom resources.
# Written by verghost (https://github.com/verghost)

usage=\
'ProxPop: Proxychains config populator
A simple bash script that populates the proxychains config (/etc/proxychains.conf) with proxies from custom resources.

usage: proxpop.sh [options]
	[Proxy Types] For each type, you can chosse to only fetch the first n proxies (ex. proxpop.sh --http 4).
	--http   [n]   Populate HTTP proxies
	--socks4 [n]   Populate SOCKS4 proxies
	--scosk5 [n]   Populate SCOKS5 proxies
	--all    [n]   Populate all types of proxies (HTTP, SOCKS4 & SOCKS5)
	
	[Template Options]
	-t, --template Use custom template file (Default is proxychains.template)
	-q, --quiet    Use proxychains quiet mode
	--no-proxy-dns Do NOT proxy DNS requests (this is ON by default)
	--use-strict   Use strict chain in template file (default is dynamic_chain)
	--use-random   Use random chain. You can optionally provide chain length: proxpop.sh ... --use-random 3 (Default length is: 2)
	
	[Saftey Options]
	-k, --keep     Keep old configuration file (Old file is copied to /usr/share/proxpop/proxychains.old)
	--review   Review final configuration file before finalizing (-s/--silent does not apply to this option)
	
	[Fetch Options]
	--tor-fetch    Try to fetch resources through TOR (must have TOR installed, may not work since many sites block TOR nodes)
	--proxy-fetch  Try to fetch resources through proxy (may not work if proxychains is improperly configured)
	
	[Other Options]
	-r, --resource Specify a custom resource file (ex. proxpop.sh ... -r resource.txt)
	-s, --silent   Do not display output (does not apply to --review, torify or proxychains)
	-h, --help     Show this message

NOTES:
By default, some free proxies from the ProxyScrap API are used.
To specify custom locations a FILE can be supplied to the script. This overrides the default locations.

The custom resource FILE must specify resources one at a time, each on their own line. 
Each resource lines should have the following format TYPE:URL where TYPE is one of HTTP, SOCKS4, SOCKS5 (This is CASE SENSITIVE)
As an example, see the defaults resource file:

Each resource should return a list of proxy IPs and PORT in the IP:PORT formate, for example:
103.31.251.17:8080
37.255.248.77:8080
221.182.31.54:8080
106.14.237.164:8080
'

TEMPLATE_MODE="dynamic_chain"
declare -A PP_TOPTS # template options
PP_TOPTS["quiet_mode"]="#" # this indicates that we will comment out this option
PP_TOPTS["proxy_dns"]=""
PP_TOPTS["chain_len"]="#"
PP_TOPTS["tcp_read_time_out"]=15000
PP_TOPTS["tcp_connect_time_out"]=8000

TMP_HTTP="/tmp/http_prox"
TMP_SOCKS4="/tmp/socks5_prox"
TMP_SOCKS5="/tmp/socks4_prox"
TMP_CONF="/tmp/proxychains.conf"

PC_CONF_PATH="/etc/proxychains.conf"
OLD_CONFIG="/usr/share/proxpop/proxychains.old"

PP_CURL="curl" # curl function

RESOURCE_FILE="/usr/share/proxpop/resources.default" # Defaults
TEMPLATE_FILE="/usr/share/proxpop/proxychain.template"


# Util functions

pp_echo() {
	if [[ ! $PROXPOP_SILENT ]]; then echo "$*"; fi
}

pp_error() {
	local code=$2; [[ "$code" == "" ]] && code=1;
	echo "$1" >&2
	exit $code
}

pp_exit() {
	echo "Cleaning up..."
	rm -f $TMP_CONF
	rm -f $TMP_HTTP $TMP_SOCKS4 $TMP_SOCKS5
	
	echo "| -------- |"
	echo "| ALL DONE |"
	echo "| -------- |"
	
	exit $1
}

# Curl something and them append output to 
pp_curl() {
	local out=$1; shift;
	
	if [[ $PROXPOP_TORFETCH ]]; then 
		torify curl -s -o $out "$*"
	elif [[ $PROXPOP_PROXYFETCH ]]; then
		proxychains curl -s -o $out "$*"
	else
		curl -s -o $out $*
	fi
}

add_proxy() {
	local type=$1
	local file=$2
	while IFS= read -r ipp; do
		echo "$type $ipp" | awk -F':' '{print $1,$2}' >> $TMP_CONF
	done < $file
	rm -f $file # clear temp file
}

fetch_proxies() {
	pp_echo "Fetching proxies..."
	echo "[ProxyList]" >> $TMP_CONF
	while IFS= read -r rec; do
		if [[ "${rec:0:4}" == "http" ]] && [[ ! "$PROXPOP_HTTP" == "" ]]; then
			pp_curl $TMP_HTTP "${rec:5}"
			add_proxy "http" $TMP_HTTP
		elif [[ "${rec:0:6}" == "socks4" ]] && [[ ! "$PROXPOP_SOCKS4" == "" ]]; then
			pp_curl $TMP_SOCKS4 "${rec:6}"
			add_proxy "socks4" $TMP_SOCKS4
		elif [[ "${rec:0:6}" == "socks5" ]] && [[ ! "$PROXPOP_SOCKS5" == "" ]]; then
			pp_curl $TMP_SOCKS5 "${rec:6}"
			add_proxy "socks5" $TMP_SOCKS5
		fi
	done < $RESOURCE_FILE
}

populate() {
	pp_echo ""
	pp_echo "Starting ProxPop..."
	
	if [[ $PROXPOP_KEEP ]]; then # keep old config 
		cp -f $PC_CONF_PATH $OLD_CONFIG
	fi
	
	pp_echo "Writing configuration file..."
	touch $TMP_CONF # create base config file
	echo $TEMPLATE_MODE > $TMP_CONF
	for k in "${!PP_TOPTS[@]}"; do
		if [[ ! "${PP_TOPTS[$k]:0:1}" == "#" ]]; then
			echo "$k ${PP_TOPTS[$k]}" >> $TMP_CONF
		fi
	done
	
	fetch_proxies
	
	chmod 644 $TMP_CONF
	
	sleep 1
	pp_echo "New configuration is ready!"
	
	if [[ $PROXPOP_REVIEW ]]; then
		sleep 1
		echo "Please review the new file when it appears..."
		sleep 2

		more $TMP_CONF
		echo ""

		while true; do
			echo -n "If this OK? (y/N): "
			read yorn
			if [[ "$yorn" == "y" ]] || [[ "$yorn" == "Y" ]]; then
				echo "Replacing current config..."
				mv -f $TMP_CONF $PC_CONF_PATH
				break
			elif [[ "$yorn" == "n" ]] || [[ "$yorn" == "N" ]]; then
				echo "OK, aborting..."
				pp_exit 0
			else
				echo "Not a valid response!"
			fi
		done
	else
		mv -f $TMP_CONF $PC_CONF_PATH
	fi
	
	pp_exit 0
}

set_template_mode() {
	if [[ "$TEMPLATE_MODE" == "dynamic_chain" ]]; then # is this still the default?
		TEMPLATE_MODE="$1"
	else
		pp_error "You must only specify one mode!"
	fi
}

get_first_n() {
	local ret="$2" # default value
	case "$1" in # https://stackoverflow.com/a/3951175
		''|*[!0-9]*) ;; # negates strings, floating point and negative numbers
		*) ret=$1 ;;
	esac
	echo "$ret"
}

if [ "$EUID" -ne 0 ]
	then echo "Error: This script must be run as root!"
	exit
fi

while [[ "$#" -gt 0 ]]; do
	case "$1" in
	# Proxy types
	--http) 
		shift
		PROXPOP_HTTP="$(get_first_n $1 all)"
		[[ ! "$PROXPOP_HTTP" == "all" ]] && shift
	;;
	--socks4) 
		shift
		PROXPOP_SOCKS4="$(get_first_n $1 all)"
		[[ ! "$PROXPOP_SOCKS4" == "all" ]] && shift
	;;
	--socks5)
		shift
		PROXPOP_SOCKS5="$(get_first_n $1 all)"
		[[ ! "$PROXPOP_SOCKS5" == "all" ]] && shift
	;;
	--all)
		shift
		PROXPOP_HTTP="$(get_first_n $1 all)"
		PROXPOP_SOCKS4="$PROXPOP_HTTP"
		PROXPOP_SOCKS5="$PROXPOP_HTTP"
		[[ ! "$PROXPOP_HTTP" == "all" ]] && shift
	;;
	
	# Template options
	-t|--template)
		shift
		if [[ -f $1 ]]; then
			TEMPLATE_FILE=$1
			shift
		else
			pp_error "$1 is not a file!"
		fi
	;;
	-q|--quiet) PP_TOPTS["quiet_mode"]=""; shift; ;;
	--no-proxy-dns) PP_TOPTS["proxy_dns"]="#"; shift; ;;
	--use-strict) set_template_mode "strict_chain"; shift; ;;
	--use-random)
		set_template_mode "random_chain"
		shift
		local chain_len="$(get_first_n $1 t)"
		if [[ "$chain_len" == "t" ]]; then PP_TOPTS["chain_len"]="= 2"; 
		else shift; PP_TOPTS["chain_len"]="= ${chain_len}"; fi
	;;
	
	# Safety options
	-k|--keep) PROXPOP_KEEP=1; shift; ;;
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
	-r|--resource)
		shift
		if [[ -f $1 ]]; then
			RESOURCE_FILE=$1
			shift
		else
			pp_error "$1 is not a file!"
		fi
	;;
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

# Run if a proxy type has been specified
if [[ $PROXPOP_HTTP ]] || [[ $PROXPOP_SOCKS4 ]] || [[ $PROXPOP_SOCKS5 ]]; then
	populate
else
	echo "You must supply at least one type of proxy to populate (--http, --socks4, --socks5, --all)"
	echo "For usage, type: proxpop.sh --help"
fi
