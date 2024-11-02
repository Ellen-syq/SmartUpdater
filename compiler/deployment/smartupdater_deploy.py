#!/usr/bin/env python

import argparse
import os
import logging
import sys
import smartupdater_D


logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s: %(message)s')
log = logging.getLogger()

parser = argparse.ArgumentParser(description="SmartUpdater Command Line Interface for Contract Conversion")
parser.add_argument("contract_source", type=str, help="Path to the Solidity contract source file")
args = parser.parse_args()

input_file = args.contract_source
if not os.path.exists(input_file):
    log.error("Error: The specified contract source file does not exist.")
    sys.exit(1)

log.info("Starting Maintenance!")
log.info("Compiling Solidity code %s", args.contract_source)
name = os.path.splitext(os.path.basename(input_file))[0]
smartupdater_D.mainfunc(input_file, name)


log.info("Accomplish！")
log.info("Exit！")