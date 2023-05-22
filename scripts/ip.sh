#!/bin/bash

set -u

hostname --all-ip-addresses | aws '{print $1}'
