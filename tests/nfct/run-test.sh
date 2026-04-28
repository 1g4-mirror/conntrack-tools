#!/bin/bash

_UID=`id -u`
if [ $_UID -ne 0 ]
then
	echo "Run this test as root"
	exit 1
fi

test -x test || gcc test.c -o test
exec unshare -n ./test timeout
