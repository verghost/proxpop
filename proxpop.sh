#!/bin/bash
# ProxPop v0: A simple bash script that populates the proxychains config (/etc/proxychains.conf) with proxies from custom resources.
# Written by verghost (https://github.com/verghost)
#

usage=\
'ProxPop: Proxychains config populator
A simple bash script that populates the proxychains config (/etc/proxychains.conf) with proxies from custom resources.

usage: proxpop.sh [options] [FILE]
	[Proxy Types]
	--http         Populate HTTP proxies
	--socks4       Populate SOCKS4 proxies
	--scosk5       Populate SCOKS5 proxies
	--all          Populate all types of proxies (HTTP, SOCKS4 & SOCKS5)
	
	[Saftey Options]
	-k, --keep     Keep old configuration file (Old file is copied to /usr/share/proxpop/proxychains.old)
	-r, --review   Review final configuration file before finalizing (-q/--quiet does not apply to this option)
	
	[Fetch Options]
	--tor-fetch    Try to fetch resources through TOR (must have TOR installed, may not work since many sites block TOR nodes)
	--proxy-fetch  Try to fetch resources through proxy (may not work if proxychains is improperly configured)
	
	[Other Options]
	-t, --template Custom template file (Default is proxychains.template)
	-q, --quiet    Do not display output (does not apply to --review, torify or proxychains)
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

TMP_HTTP="/tmp/http_prox_${RANDOM}"
TMP_SOCKS4="/tmp/socks5_prox_${RANDOM}"
TMP_SOCKS5="/tmp/socks4_prox_${RANDOM}"
TMP_CONF="/tmp/proxychains_${RANDOM}.conf"

PC_CONF_PATH="/etc/proxychains.conf"
OLD_CONFIG="/usr/share/proxpop/proxychains.old"

PP_CURL="curl" # curl function

RESOURCE_FILE="/usr/share/proxpop/resources.default" # Defaults
TEMPLATE_FILE="/usr/share/proxpop/proxychain.template"

pp_echo() {
	if [[ ! $PROXPOP_QUIET ]]; then echo "$*"; fi
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

add_proxy() {
	local type=$1
	local file=$2
	while IFS=, read -r ipp; do
		echo "$type $ipp" | awk -F':' '{print $1,$2}' >> $TMP_CONF
	done < $file
}

pp_curl() {
	local out=$1; shift;
	local tmp="./output_${RANDOM}.tmp"
	
	if [[ $PROXPOP_TORFETCH ]]; then 
		torify curl -s -o "$tmp" $*
	elif [[ $PROXPOP_PROXYFETCH ]]; then
		proxychains curl -s -o "$tmp" $*
	else
		curl -s -o "$tmp" $* >> $out
	fi
	
	cat  >> $out
	rm -f $out
}

fetch_proxies() {
	pp_echo "Fetching proxies..."
	
	while IFS=, read -r rec; do
		if [[ "${rec:0:4}" == "http" ]] && [[ $PROXPOP_HTTP ]]; then
			pp_curl "$TMP_HTTP" "${rec:5}"
		elif [[ "${rec:0:5}" == "socks4" ]] && [[ $PROXPOP_SOCKS4 ]]; then
			pp_curl "$TMP_SOCKS4" "${rec:6}"
		elif [[ "${rec:0:5}" == "socks5" ]] && [[ $PROXPOP_SOCKS5 ]]; then
			pp_curl "$TMP_SOCKS5" "${rec:6}"
		fi
	done < $RESOURCE_FILE
}

populate() {
	pp_echo ""
	pp_echo "Starting ProxPop..."
	
	cp $TEMPLATE_FILE $TMP_CONF # create base config file
	
	fetch_proxies
	
	sleep 1
	pp_echo "New configuration is ready!"
	
	if [[ $PROXPOP_REVIEW ]]; then
		sleep 1
		echo "Please review the new file when it appears..."
		sleep 3

		more $TMP_CONF
		echo ""

		while true; do
			echo -n "If this OK? (y/N): "
			read yorn
			if [[ "$yorn" == "y" ]] || [[ "$yorn" == "Y" ]]; then
				echo "Replacing current config..."
				mv $TMP_CONF $PC_CONF_PATH
				break
			elif [[ "$yorn" == "n" ]] || [[ "$yorn" == "N" ]]; then
				echo "OK, aborting..."
				pp_exit 0
			else
				echo "Not a valid response!"
			fi
		done
	fi
	
	pp_exit 0
}

while [[ "$#" -gt 0 ]]; do
	case "$1" in
	# Proxy types
	--http) PROXPOP_HTTP=1; shift; ;;
	--socks4) PROXPOP_SOCKS4=1; shift; ;;
	--socks5) PROXPOP_SOCKS5=1; shift; ;;
	--all)
		PROXPOP_HTTP=1
		PROXPOP_SOCKS4=1
		PROXPOP_SOCKS5=1
		shift
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
			echo "Torify is not installed!" >&2
			exit 1
		fi
	;;
	--proxy-fetch) PROXPOP_PROXYFETCH=1; shift; ;;
	
	# Other Options
	-t|--template)	shift; TEMPLATE_FILE=$1; shift; ;;
	-q|--quiet) PROXPOP_QUIET=1; shift; ;;
	-h|--help) echo "$usage"; exit; ;;
	
	-*) # handle unknown
		echo "Unknown option: $1" >&2
		exit 1
	;;
	
	*) # handle file
		if [[ -f $1 ]]; then
			PROXPOP_CUSTOM=$1
			shift
		else
			echo "$1 is not a file!" >&2
			exit 1
		fi
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
