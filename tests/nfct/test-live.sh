#!/bin/sh
#
# simple testing for cttimeout infrastructure using one single computer
#

die() {
	echo "$@"
	exit 1
}

if [ "$1" != "run" ] ;then
	hping3 -h > /dev/null || die "hping3 is missing"
	exec unshare -n ./$0 "run"
fi

warn() {
	echo "WARN: $@"
}

tmp=$(mktemp)
cleanup()
{
	ip link del eth0
	rm -f "$tmp"
}
trap cleanup EXIT

ret=0
check_timeout() {
	local proto="$1"
	local timeout="$2"

	if ! grep '[NEW]' "$tmp" | grep "$proto $timeout";then
		warn "Did not find expected output, got:"
		cat "$tmp"
		echo ----- EOF -----
		ret=1
	fi
}

add_rule() {
	local proto="$1"
	local name="$2"

	echo "Check timeout policy $name for protocol $proto"
	iptables -I OUTPUT -t raw -p "$proto" -j CT --timeout "$name" || die "can't add -p $proto -j CT $name"
}

rm_rules() {
	local proto="$1"
	local name="$2"

	iptables -D OUTPUT -t raw -p $proto -j CT --timeout "$name" || warn "can't remove $proto $name rule"
	nfct del timeout "$name" || warn "can't remove $name policy"
}

ip link add eth0 type dummy
ip link set eth0 up
ip link set lo up
ip addr add 10.0.0.1/8 dev eth0
ip route add default via 10.0.0.99 dev eth0

WAIT_BETWEEN_TESTS=5

#
# No.1: test generic timeout policy
#
conntrack -E -p 13 > "$tmp" 2>/dev/null &
pid=$!

nfct add timeout "test-generic" inet generic timeout 3 || die "can't add generic timeout"
add_rule 13 "test-generic"
hping3 -c 1 -I eth0 -0 8.8.8.8 -H 13 > /dev/null 2>&1
check_timeout 13 3
kill $pid

sleep $WAIT_BETWEEN_TESTS
rm_rules 13 "test-generic"

#
# No.2: test TCP timeout policy
#

conntrack -E -p tcp > "$tmp" 2>/dev/null &
pid=$!

nfct add timeout test-tcp inet tcp syn_sent 2 || die "can't add tcp timeout policy"
add_rule "tcp" "test-tcp"
hping3 -S -p 80 -s 5050 8.8.8.8 -c 1 > /dev/null 2>&1

check_timeout 6 2
kill $pid

sleep $WAIT_BETWEEN_TESTS
rm_rules "tcp" "test-tcp"

#
# No. 3: test ICMP timeout policy
#

conntrack -E -p icmp > "$tmp" 2>/dev/null &
pid=$!

nfct add timeout test-icmp inet icmp timeout 4 || die "can't add test-icmp policy"
add_rule "icmp" "test-icmp"

hping3 -1 8.8.8.8 -c 2 > /dev/null 2>&1

check_timeout 1 4
kill "$pid"

sleep $WAIT_BETWEEN_TESTS
rm_rules "icmp" "test-icmp"

exit $ret
