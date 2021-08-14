#!/bin/bash
#set -x
none="\e[m"
red="\e[1;31m"
cyan="\e[1;36m"
green="\e[1;32m"
yellow="\e[1;33m"

# Determine the script name and absolute root path of the project
SCRIPT=$(basename $0)
SCRIPT_DIR=$(readlink -f $(dirname $BASH_SOURCE[0]))

testing()
{
  echo testing
}

# Utility functions
# -------------------------------------------------------------------------------------------------

check()
{
  if [ $? -ne 0 ]; then
    echo -e "${red}failed!${none}"
    exit 1
  else
    echo -e "${green}success!${none}"
  fi
}

# Main entry point
# -------------------------------------------------------------------------------------------------
header()
{
  echo -e "${cyan}CLU${none} provides automation for the Arch Linux ecosystem"
  echo -e "${cyan}------------------------------------------------------------------${none}"
}
usage()
{
  header
  echo -e "Usage: ${cyan}./${SCRIPT}${none} [options]\n"
  echo -e "Options:"
  echo -e "  CMD              Run the given CMD"
  echo -e "  -h               Display usage help\n"
  echo -e "Examples:"
  echo -e "  ${green}Build everything:${none} ./${SCRIPT} -a"
  echo
  exit 1
}
while getopts "h" opt; do
  case $opt in
    h) usage;;
  esac
done
[ $(($OPTIND -1)) -eq 0 ] && usage

# Invoke the testing function if given
if [ "x${ARG}" == "xtest" ]; then
  echo "testing"
elif [ "x${ARG}" == "xradio" ]; then
  echo "radio"
fi

# vim: ft=sh:ts=2:sw=2:sts=2
