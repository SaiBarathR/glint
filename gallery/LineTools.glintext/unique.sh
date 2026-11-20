#!/bin/sh
# Print each line the first time it appears.
/usr/bin/awk '!seen[$0]++'
