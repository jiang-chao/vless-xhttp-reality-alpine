#!/bin/bash

args=$@
is_sh_ver=v1.18

script_dir='/etc/sing-box/sh'
[[ -f "$script_dir/src/xhttp.sh" ]] || script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ ${1,,} == xhttp ]]; then
    exec bash "$script_dir/src/xhttp.sh" "${@:2}"
fi
if [[ ${1,,} == add && ${2,,} =~ ^(xhttp|vless-xhttp-reality|xhttp-reality)$ ]]; then
    [[ ${3,,} == help || ${3,,} == -h || ${3,,} == --help ]] && exec bash "$script_dir/src/xhttp.sh" help
    exec bash "$script_dir/src/xhttp.sh" add "${@:3}"
fi

. /etc/sing-box/sh/src/init.sh
