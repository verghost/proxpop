# ProxPop: Proxychains config populator
A simple bash script that populates the proxychains config (/etc/proxychains.conf) with proxies from custom resources.

```
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
```

## NOTES:
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
