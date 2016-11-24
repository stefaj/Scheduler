#!/bin/bash
set -e
stack install .
stack exec -- Client "196.252.189.152" "10051" "196.252.189.152:10052:0"
