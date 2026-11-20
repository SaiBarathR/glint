#!/bin/sh
# Random order: tag every line with a random number, sort on it, then drop the tag.
# The seed mixes the time with this process's ID, so two shuffles in the same second differ.
/usr/bin/awk -v pid="$$" 'BEGIN { srand(); t = srand(); srand(t * 100000 + pid) } { printf "%.12f\t%s\n", rand(), $0 }' \
  | /usr/bin/sort -n | /usr/bin/cut -f 2-
