#!/usr/bin/env sh
# env.cgi - CGI script to dump server environment variables

# Print HTTP header
printf 'Content-Type: text/plain; charset=utf-8\r\n'
printf '\r\n'

# Dump environment variables
env
