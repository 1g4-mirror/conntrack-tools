#!/bin/bash

if [ $UID -ne 0 ]
then
	echo "You must be root to run this test script"
	exit 0
fi

ret=0
R1=""
R2=""
NS1=""
NS2=""
statedir=""

die() {
	echo "Error: $@"
	exit 1
}

warn() {
	echo "Error: $@"
	ret=1
}

cleanup() {
	for n in "$R1" "$R2" "$NS1" "$NS2"; do
		kill $(ip netns pid "$n") 2>/dev/null
		ip netns del "$n"
	done
	test -d "$statedir" && (
		rm -f "$statedir/r1"
		rm -f "$statedir/r2"
		rm -f "$statedir/ns1"
		rm -f "$statedir/ns2"
		rmdir "$statedir"
	)
}

dump_state() {
	statedir="$(mktemp -d -t ctd-state-XXXXXXXX)" || exit 1

	echo "$R1" > "$statedir/r1"
	echo "$R2" > "$statedir/r2"
	echo "$NS1" > "$statedir/ns1"
	echo "$NS2" > "$statedir/ns2"
}

restore_state() {
	read R1 < "$statedir/r1"
	read R2 < "$statedir/r2"
	read NS1 < "$statedir/ns1"
	read NS2 < "$statedir/ns2"
}

start () {
	local rnd=$(mktemp -u XXXXXXXX)

	R1="ctd-r1-$rnd"
	R2="ctd-r2-$rnd"
	NS1="ctd-ns1-$rnd"
	NS2="ctd-ns2-$rnd"

	for n in "$R1" "$R2" "$NS1" "$NS2"; do
		ip netns add "$n"
	done

	ip link add veth0 netns "$NS1" type veth peer name veth1 netns "$R1"
	ip link add veth0 netns "$R1" type veth peer name veth0 netns "$NS2"
	ip link add veth2 netns "$R1" type veth peer name veth0 netns "$R2"

	ip -net "$NS1" addr add 192.168.10.2/24 dev veth0
	ip -6 -net "$NS1" addr add bbbb::2/64 dev veth0
	ip -net "$NS1" link set up dev veth0
	ip -net "$NS1" ro add 10.0.1.0/24 via 192.168.10.1 dev veth0
	ip -6 -net "$NS1" ro add aaaa::/64 via bbbb::1 dev veth0

	ip -net "$R1" addr add 10.0.1.1/24 dev veth0
	ip -net "$R1" addr add 192.168.10.1/24 dev veth1
	ip -6 -net "$R1" addr add aaaa::1/64 dev veth0
	ip -6 -net "$R1" addr add bbbb::1/64 dev veth1
	ip -net "$R1" link set up dev veth0
	ip -net "$R1" link set up dev veth1
	ip -net "$R1" route add default via 192.168.10.2
	ip -6 -net "$R1" route add default via bbbb::2
	ip netns exec "$R1" sysctl -q net.ipv4.ip_forward=1
	ip netns exec "$R1" sysctl -q net.ipv6.conf.all.forwarding=1

	ip -net "$R1" addr add 192.168.100.2/24 dev veth2
	ip -6 -net "$R1" addr add cccc::2/96 dev veth2
	ip -net "$R1" link set up dev veth2
	ip -net "$R2" addr add 192.168.100.3/24 dev veth0
	ip -6 -net "$R2" addr add cccc::3/96 dev veth0
	ip -net "$R2" link set up dev veth0

	ip -net "$NS2" addr add 10.0.1.2/24 dev veth0
	ip -6 -net "$NS2" addr add aaaa::2/64 dev veth0
	ip -net "$NS2" link set up dev veth0
	ip -net "$NS2" route add default via 10.0.1.1
	ip -6 -net "$NS2" route add default via aaaa::1

	echo 1 > /proc/sys/net/netfilter/nf_log_all_netns

	ip netns exec "$R1" nft -f ruleset-nsr1.nft
	ip netns exec "$R1" conntrackd -C conntrackd-nsr1.conf -d
	ip netns exec "$R2" conntrackd -C conntrackd-nsr2.conf -d
}

selftest() {
	# This will time out, but we only want to make sure this appears both in nsr1 and nsr2 conntrackd
	# instances.
	timeout 10 ip netns exec "$NS1" socat -u STDIN TCP-connect:10.0.1.31:12345 > /dev/null &
	local pid=$!

	sleep 1
	if ! ip netns exec "$R1" conntrackd -C conntrackd-nsr1.conf -i | grep -q "src=192.168.10.2 dst=10.0.1.31"; then
		warn "nsr1 had no record in internal cache."
	fi

	if ! ip netns exec "$R2" conntrackd -C conntrackd-nsr2.conf -e | grep -q "src=192.168.10.2 dst=10.0.1.31"; then
		warn "nsr2 had no record in external cache."
	fi

	if [ $ret -eq 0 ];then
		echo "PASS: Found connection in external cache in nsr2."
		kill $pid
	fi
}

case $1 in
start)
	trap cleanup EXIT
	start
	dump_state
	echo "Running with: $NS1 $NS2 $R1 $R2, stop with $0 stop $statedir"
	trap - EXIT
	;;
stop)
	if [ "$2"x = ""x ]; then
		echo "$0 stop <statedir>"
	fi
	test -d "$2" || die "$2 not found"
	statedir="$2"
	trap cleanup EXIT
	restore_state
	;;
test)
	trap cleanup EXIT
	start
	selftest
	;;
*)
	echo "$0 [start|stop|test]"
	;;
esac

exit $ret
