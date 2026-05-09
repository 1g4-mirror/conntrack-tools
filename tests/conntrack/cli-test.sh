#!/bin/bash

CONNTRACK=../../src/conntrack

SRC=1.1.1.1
DST=2.2.2.2
SPORT=2005
DPORT=21

ret=0
lret=0

assert() {
	local r="$1"

	if [ $r -ne 0 ]; then
		[ "$ret" -eq 0 ] && ret="$r"
		echo "FAIL: bulk-load-stress.sh: $@"
	else
		echo "PASS: bulk-load-stress.sh: $@"
	fi
}

case $1 in
	dump)
		$CONNTRACK -L
		assert $? "Dumping conntrack table"
		;;
	flush)
		$CONNTRACK -F
		assert $? "Flushing conntrack table"
		;;
	new)
		$CONNTRACK -I --orig-src $SRC --orig-dst $DST \
		 --reply-src $DST --reply-dst $SRC -p tcp \
		 --orig-port-src $SPORT  --orig-port-dst $DPORT \
		 --reply-port-src $DPORT --reply-port-dst $SPORT \
		--state LISTEN -u SEEN_REPLY -t 50
		assert $? "creating a new conntrack"
		;;
	new-simple)
		$CONNTRACK -I -s $SRC -d $DST \
		-p tcp --sport $SPORT  --dport $DPORT \
		--state LISTEN -u SEEN_REPLY -t 50
		assert $? "creating a new conntrack (simplified)"
		;;
	new-nat)
		$CONNTRACK -I -s $SRC -d $DST \
		-p tcp --sport $SPORT  --dport $DPORT \
		--state LISTEN -u SEEN_REPLY -t 50 --dst-nat 8.8.8.8
		assert $? "creating a new conntrack (NAT)"
		;;
	get)
		$CONNTRACK -G -s $SRC -d $DST \
		-p tcp --sport $SPORT --dport $DPORT
		assert $? "getting a conntrack"
		;;
	change)
		$CONNTRACK -U -s $SRC -d $DST \
		-p tcp --sport $SPORT --dport $DPORT \
		--state TIME_WAIT -u ASSURED,SEEN_REPLY -t 500
		assert $? "change a conntrack"
		;;
	delete)
		$CONNTRACK -D -s $SRC -d $DST \
		-p tcp --sport $SPORT --dport $DPORT
		assert $? "delete a conntrack"
		;;
	output)
		proc=$(cat /proc/net/nf_conntrack | wc -l)
		netl=$($CONNTRACK -L | wc -l)
		count=$(cat /proc/sys/net/netfilter/nf_conntrack_count)
		if [ $proc -ne $netl ]; then
			echo "proc is $proc and netl is $netl and count is $count"
		else
			if [ $proc -ne $count ]; then
				echo "proc is $proc and netl is $netl and count is $count"
			else
				echo "now $proc"
			fi
		fi
		assert $? "output: check proc and netlink entry count"
		;;
	dump-expect)
		$CONNTRACK -L expect
		assert $? "conntrack -L expect"
		;;
	flush-expect)
		$CONNTRACK -F expect
		assert $? "conntrack -F expect"
		;;
	create-expect)
		conntrack -L
		# modprobe nf_conntrack_ftp
		$CONNTRACK -I expect --orig-src $SRC --orig-dst $DST \
		--tuple-src 4.4.4.4 --tuple-dst 5.5.5.5 \
		--mask-src 255.255.255.0 --mask-dst 255.255.255.255 \
		-p tcp --orig-port-src $SPORT --orig-port-dst $DPORT \
		-t 200 --tuple-port-src 10240 --tuple-port-dst 10241\
		--mask-port-src 10 --mask-port-dst 300
		assert $? "create conntrack expectation"
		;;
	get-expect)
		$CONNTRACK -G expect --orig-src 4.4.4.4 --orig-dst 5.5.5.5 \
		--p tcp --orig-port-src 10240 --orig-port-dst 10241 \
		--reply-port-src $DPORT --reply-port-dst $SPORT
		assert $? "get conntrack expectation"
		;;
	delete-expect)
		$CONNTRACK -D expect --orig-src 4.4.4.4 \
		--orig-dst 5.5.5.5 -p tcp --orig-port-src 10240 \
		--orig-port-dst 10241 \
		--reply-port-src $DPORT --reply-port-dst $SPORT
		assert $? "delete conntrack expectation"
		;;
	all-ns)
		unshare -n "$0" all
		assert $? "all-ns"
		;;
	all)
		for T in new delete new-simple flush new-nat \
			dump \
			change output \
			flush ; do
			"$0" "$T"
			assert $? "all: $T"
		done
		;;
	*)
		echo "Usage: $0 [dump"
		echo "		|new"
		echo "		|new-simple"
		echo "		|new-nat"
		echo "		|get"
		echo "		|change"
		echo "		|delete"
		echo "		|output"
		echo "		|flush"
		echo "		|dump-expect"
		echo "		|flush-expect"
		echo "		|create-expect"
		echo "		|get-expect"
		echo "		|delete-expect]"
		echo "		|all-ns"
		echo "		|all"
		;;
esac

exit $ret
