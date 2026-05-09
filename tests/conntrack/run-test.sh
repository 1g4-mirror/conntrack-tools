#!/bin/bash

if [ $UID -ne 0 ]
then
	echo "Run this test as root"
	exit 1
fi

make test

./test testcases
