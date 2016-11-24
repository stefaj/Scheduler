#!/bin/bash
set -e
stack install .
stack exec -- Server "196.252.189.152" "10052"
