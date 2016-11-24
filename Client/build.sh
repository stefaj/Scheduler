#!/bin/bash
set -e
stack install .
stack exec -- Scheduler
