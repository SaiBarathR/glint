#!/bin/sh
# Shortest first; -s keeps lines of the same length in their original order.
/usr/bin/awk '{ printf "%d\t%s\n", length($0), $0 }' | /usr/bin/sort -n -s -k 1,1 | /usr/bin/cut -f 2-
