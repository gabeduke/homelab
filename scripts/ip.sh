#!/bin/bash

set -u

hostname --all-ip-addresses | awk '{print $1}'
