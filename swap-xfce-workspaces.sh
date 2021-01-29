#!/usr/bin/env bash

# Bash strict mode: http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -o nounset   # Using an undefined variable is fatal
set -o errexit   # A sub-process/shell returning non-zero is fatal
# set -o pipefail  # If a pipeline step fails, the pipelines RC is the RC of the failed step
# set -o xtrace    # Output a complete trace of all bash actions; uncomment for debugging

# IFS=$'\n\t'  # Only split strings on newlines & tabs, not spaces.

function init() {
  readonly script_path="${BASH_SOURCE[0]:-$0}"
  readonly script_dir="$(dirname "$(readlink -f "$script_path")")"
  readonly script_name="$(basename "$script_path")"
  
  # Get the names of all the workspaces
  ws_names=()
  while read -r name; do
    ws_names+=("$name")
  done < <(xfconf-query -c xfwm4 -p /general/workspace_names | tail -n +3)

  # Get current workspace details from wmctrl
  current_ws_idx=$(wmctrl -d | grep '*' | cut -d " " -f1)
  current_ws_name=${ws_names[$current_ws_idx]}
  max_ws_idx=$(wmctrl -d | wc -l)

  verbose=false

  setup_colors
  parse_params "$@"
}

usage() {
  cat <<EOF

Swap or move the current Xfce workspace.

${bld}USAGE${off}
  $script_name <workspace num>|prev|next

${bld}ARGUMENTS${off}
  <workspace num>  the target workspace id. Expects XFCE workspace numbers, starting from 1.
  prev             swap current workspace with the previous one
  next             swap current workspace with the next one
  help             show this help

${bld}OPTIONS${off}
  -h, --help       show this help
  -v, --verbose    show verbose/debug output

${bld}EXAMPLES${off}
  ${gry}# Swap the current workspace with any other by passing in the target workspace id:
  # NOTE: This expects XFCE workspace numbers, which start from 1.${off}
  $ $script_name <target workspace id>

  ${gry}# Move the current workspace left or right, by swapping it with the previous or next workspace.${off}
  $ $script_name prev
  $ $script_name next
EOF
  exit
}

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    # Control sequences for fancy colours
    readonly gry="$(tput setaf 240 2> /dev/null || true)"
    readonly bld="$(tput bold 2> /dev/null || true)"
    readonly off="$(tput sgr0 2> /dev/null || true)"
  else
    readonly gry=''
    readonly bld=''
    readonly off=''
  fi
}

msg() {
  echo >&2 -e "${1-}"
}

vmsg() {
  if [ "$verbose" = "true" ]; then
    msg "$@"
  fi
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  exit "$code"
}

function parse_params() {
  local param
  while [[ $# -gt 0 ]]; do
    param="$1"
    shift
    case $param in
      -h | --help | help)
        usage
        ;;
      -v | --verbose)
        verbose=true
        ;;
      *)
        # Figure out target_ws_idx
        if [[ $param =~ prev ]]; then
          # Swapping with previous workspace, wrap if at end.
          if [[ $current_ws_idx == 0 ]]; then
            target_ws_idx=$max_ws_idx
          else
            target_ws_idx=$((current_ws_idx - 1))
          fi
        elif [[ $param =~ next ]]; then
          # Swapping with next workspace, wrap if at end.
          if [[ $current_ws_idx == "$max_ws_idx" ]]; then
            target_ws_idx=0
          else
            target_ws_idx=$((current_ws_idx + 1))
          fi
        else
          if (( param == 0 )); then
            die "Target workspace was: 0. Target workspace must be from 1 to $max_ws_idx" 2
          fi
          if (( param > max_ws_idx )); then
            die "Target workspace was: $param. Target workspace must be from 1 to $max_ws_idx" 2
          fi
          # Users desktops are numbered from 1, but wmcrtl numbers from zero, so minus one.
          target_ws_idx=$((param-1))
        fi
        ;;
    esac
  done
}

init "$@"

if ! command -v wmctrl &> /dev/null
then
  die "wmctrl could not be found\n\
    $script_name requires wmctrl (tested with 1.07)\n\
    See: https://www.freedesktop.org/wiki/Software/wmctrl/" 127
fi

if [[ $# -ne 1 ]]; then
  msg "Missing parameter: Target Workspace - the workspace ID to swap with the active one."
  usage
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
vmsg "Windows on current workspace: \n$current_windows"

# Get list of window ids on target workspace
target_windows=$(wmctrl -lx | awk -v tws="$target_ws_idx" '($2 == tws) {print $1}')
vmsg "Windows on target workspace: \n$target_windows"

# Move all windows on current workspace to target
for window in ${current_windows//\\n/ }
do
  vmsg "Moving window: $window from workspace $current_ws_idx to $target_ws_idx"
  wmctrl -ir "$window" -t "$target_ws_idx"
done

# Move all windows from target to current
for window in ${target_windows//\\n/ }
do
  vmsg "Moving window: $window from workspace $target_ws_idx to $current_ws_idx"
  wmctrl -ir "$window" -t "$current_ws_idx"
done

# Swap workspace names
xfconf_cmd="xfconf-query -c xfwm4 -p /general/workspace_names"
for i in "${!ws_names[@]}"; do
    if [[ $i == "$current_ws_idx" ]]; then
      xfconf_cmd+=" -s \"$target_ws_name\""
    elif [[ $i == "$target_ws_idx" ]]; then
      xfconf_cmd+=" -s \"$current_ws_name\""
    else
      xfconf_cmd+=" -s \"${ws_names[$i]}\""
    fi
done

vmsg "Renaming workspaces: $xfconf_cmd"
eval "$xfconf_cmd"

# Switch to the target desktop
wmctrl -s $target_ws_idx