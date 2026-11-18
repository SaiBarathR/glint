#!/bin/sh
# Encode stdin as one line of standard Base64.
/usr/bin/base64 | tr -d '\n'
