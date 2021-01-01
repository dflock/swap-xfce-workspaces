#!/usr/bin/env bash

# Bash strict mode: http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -o nounset   # Using an undefined variable is fatal
set -o errexit   # A sub-process/shell returning non-zero is fatal
# set -o pipefail  # If a pipeline step fails, the pipelines RC is the RC of the failed step
# set -o xtrace    # Output a complete trace of all bash actions; uncomment for debugging

# IFS=$'\n\t'  # Only split strings on newlines & tabs, not spaces.

usage() {
  cat <<EOF

Swap or move the current Xfce workspace.

${bld}USAGE${off}
  $(basename "${BASH_SOURCE[0]}") <workspace num>|prev|next

${bld}ARGUMENTS${off}
  <workspace num>  the target workspace id. Expects XFCE workspace numbers, starting from 1.
  prev             swap current workspace with the previous one
  next             swap current workspace with the next one
  help             show this help

${bld}OPTIONS${off}
  -h, --help       show this help

${bld}EXAMPLES${off}
  ${gry}# Swap the current workspace with any other by passing in the target workspace id:
  # NOTE: This expects XFCE workspace numbers, which start from 1.${off}
  $ $(basename "${BASH_SOURCE[0]}") <target workspace id>

  ${gry}# Move the current workspace left or right, by swapping it with the previous or next workspace.${off}
  $ $(basename "${BASH_SOURCE[0]}") prev
  $ $(basename "${BASH_SOURCE[0]}") next
EOF
  exit
}

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    # Control sequences for fancy colours
    readonly red="$(tput setaf 1 2> /dev/null || true)"
    readonly grn="$(tput setaf 2 2> /dev/null || true)"
    readonly ylw="$(tput setaf 3 2> /dev/null || true)"
    readonly wht="$(tput setaf 7 2> /dev/null || true)"
    readonly gry="$(tput setaf 8 2> /dev/null || true)"
    readonly bld="$(tput bold 2> /dev/null || true)"
    readonly off="$(tput sgr0 2> /dev/null || true)"
  else
    readonly red=''
    readonly grn=''
    readonly ylw=''
    readonly wht=''
    readonly gry=''
    readonly bld=''
    readonly off=''
  fi
}

msg() {
  echo >&2 -e "${1-}"
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  exit "$code"
}

setup_colors

if ! command -v wmctrl &> /dev/null
then
  die "wmctrl could not be found\n\
    ${BASH_SOURCE[0]} requires wmctrl (tested with 1.07)\n\
    See: https://www.freedesktop.org/wiki/Software/wmctrl/" 127
fi

if [[ $# -ne 1 ]]; then
  msg "Missing parameter: Target Workspace - the workspace ID to swap with the active one."
  usage
fi

if [[ $1 == '-h' || $1 == '--help' || $1 == 'help' ]]; then
  usage
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
    die "Target workspace was: $1. Target workspace must be from 1 to $max_ws_idx" 2
  fi
  if [[ $1 > $max_ws_idx ]]; then
    die "Target workspace was: $1. Target workspace must be from 1 to $max_ws_idx" 2
  fi
  # Users desktops are numbered from 1, but wmcrtl numbers from zero, so minus one.
  target_ws_idx=$(($1-1))
fi
# Get target workspace details from wmctrl
target_ws_name=${ws_names[$target_ws_idx]}

msg "Current Workspace: $current_ws_idx: $current_ws_name"
msg "Target Workspace: $target_ws_idx: $target_ws_name"

# Bail if $current_ws_idx == the workspace to swap with
if [[ $current_ws_idx -eq $target_ws_idx ]]; then
  die "Cannot swap workspace with itself." 2
fi

# Get list of window ids on current workspace
current_windows=$(wmctrl -lx | awk -v cws="$current_ws_idx" '($2 == cws) {print $1}')
msg "Windows on current workspace: \n$current_windows"

# Get list of window ids on target workspace
target_windows=$(wmctrl -lx | awk -v tws="$target_ws_idx" '($2 == tws) {print $1}')
msg "Windows on target workspace: \n$target_windows"

# Move all windows on current workspace to target
for window in ${current_windows//\\n/ }
do
  msg "Moving window: $window from workspace $current_ws_idx to $target_ws_idx"
  wmctrl -ir "$window" -t "$target_ws_idx"
done

# Move all windows from target to current
for window in ${target_windows//\\n/ }
do
  msg "Moving window: $window from workspace $target_ws_idx to $current_ws_idx"
  wmctrl -ir "$window" -t "$current_ws_idx"
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

msg "Renaming workspaces: $xfconf_cmd"
eval $xfconf_cmd

# Switch to the target desktop
wmctrl -s $target_ws_idx