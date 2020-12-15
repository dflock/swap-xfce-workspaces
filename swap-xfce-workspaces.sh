#!/usr/bin/env bash

# Bash strict mode: http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -o nounset   # Using an undefined variable is fatal
set -o errexit   # A sub-process/shell returning non-zero is fatal
# set -o pipefail  # If a pipeline step fails, the pipelines RC is the RC of the failed step
#set -o xtrace    # Output a complete trace of all bash actions; uncomment for debugging

#IFS=$'\n\t'  # Only split strings on newlines & tabs, not spaces.

# 
# Simple script to swap the current workspace, for Xfce4.
#
# Takes one parameter, the workspace to swap with the active one. 
#

if ! command -v wmctrl &> /dev/null
then
    echo "wmctrl could not be found"
    echo "${BASH_SOURCE[0]} requires wmctrl (tested with 1.07)"
    echo "See: https://www.freedesktop.org/wiki/Software/wmctrl/"
    exit 127
fi

if [[ $# -ne 1 ]]; then
  echo "Missing parameter: Target Workspace - the workspace ID to swap with the active one."
  exit 2
fi

# Get the names of all the workspaces
ws_names=()
while read name; do
  ws_names+=("$name")
done < <(xfconf-query -c xfwm4 -p /general/workspace_names | tail -n +3)

# Get current workspace details from wmctrl
current_ws_idx=$(wmctrl -d | grep '*' | cut -d " " -f1)
current_ws_name=${ws_names[$current_ws_idx]}

max_ws_idx=$(wmctrl -d | wc -l)

# Figure out target_ws_idx
if [[ $1 =~ prev ]]; then
  # Swapping with previous workspace, wrap if at end.
  if [[ $current_ws_idx == 0 ]]; then
    target_ws_idx=$max_ws_idx
  else
    target_ws_idx=$(($current_ws_idx - 1))
  fi
elif [[ $1 =~ next ]]; then
  # Swapping with next workspace, wrap if at end.
  if [[ $current_ws_idx == $max_ws_idx ]]; then
    target_ws_idx=0
  else
    target_ws_idx=$(($current_ws_idx + 1))
  fi
else
  if [[ $1 == 0 ]]; then
    echo "Target workspace was: $1"
    echo "Target workspace must be from 1 to $max_ws_idx"
    exit 2
  fi
  if [[ $1 > $max_ws_idx ]]; then
    echo "Target workspace was: $1"
    echo "Target workspace must be from 1 to $max_ws_idx"
    exit 2
  fi
  # Users desktops are numbered from 1, but wmcrtl numbers from zero, so minus one.
  target_ws_idx=$(($1-1))
fi
# Get target workspace details from wmctrl
target_ws_name=${ws_names[$target_ws_idx]}

echo "Current Workspace: $current_ws_idx: $current_ws_name"
echo "Target Workspace: $target_ws_idx: $target_ws_name"

# Bail if $current_ws_idx == the workspace to swap with
if [[ $current_ws_idx -eq $target_ws_idx ]]; then
  echo "Cannot swap workspace with itself."
  exit 2
fi

# Get list of window ids on current workspace
current_windows=$(wmctrl -lx | awk -v cws="$current_ws_idx" '($2 == cws) {print $1}')
echo -e "Windows on current workspace: \n$current_windows"

# Get list of window ids on target workspace
target_windows=$(wmctrl -lx | awk -v tws="$target_ws_idx" '($2 == tws) {print $1}')
echo -e "Windows on target workspace: \n$target_windows"

# Move all windows on current workspace to target
for window in ${current_windows//\\n/ }
do
  echo "Moving window: $window from workspace $current_ws_idx to $target_ws_idx"
  # wmctrl -i "$window" -t "$target_ws_idx"
done

# Move all windows from target to current
for window in ${target_windows//\\n/ }
do
  echo "Moving window: $window from workspace $target_ws_idx to $current_ws_idx"
  # wmctrl -i "$window" -t "$current_ws_idx"
done

# Swap workspace names
xfconf_cmd="xfconf-query -c xfwm4 -p /general/workspace_names"
for i in ${!ws_names[@]}; do
    if [[ $i == $current_ws_idx ]]; then
      xfconf_cmd+=" -s \"$target_ws_name\""
    elif [[ $i == $target_ws_idx ]]; then
      xfconf_cmd+=" -s \"$current_ws_name\""
    else
      xfconf_cmd+=" -s \"${ws_names[$i]}\""
    fi
done

echo "$xfconf_cmd"
# eval $xfconf_cmd