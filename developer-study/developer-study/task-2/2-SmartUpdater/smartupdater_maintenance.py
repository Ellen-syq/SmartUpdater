#!/usr/bin/env python

import argparse
import os
import logging
import sys
import smartupdater_M

# 设置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s: %(message)s')
log = logging.getLogger()


parser = argparse.ArgumentParser(description="SmartUpdater Command Line Interface for Contract Maintenance")
parser.add_argument("contract_sname", type=str, help="Name of the Solidity contract source file")
parser.add_argument("requirement_source", type=str, help="Path to the requirement source file")
args = parser.parse_args()

# 检查输入文件是否存在
if not os.path.exists(args.contract_source+".sol"):
    log.error("Error: The specified contract source file does not exist.")
    sys.exit(1)

if not os.path.exists(args.requirement_source):
    log.error("Error: The specified requirement source file does not exist.")
    sys.exit(1)

log.info("Contract name: %s", args.contract_source)
log.info("Requirement Source: %s", args.requirement_source)

smartupdater_M.main(args.contract_source,args.requirement_source)

log.info("Accomplish！")
log.info("Exit！")


