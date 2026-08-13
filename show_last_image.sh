#!/usr/bin/env bash
# Preview the most recently generated image in out/ with Quick Look.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out_dir="${script_dir}/out"

latest="$(ls -t "${out_dir}"/*.png 2>/dev/null | head -1)"

if [[ -z "${latest}" ]]; then
    echo "No PNG files found in ${out_dir}" >&2
    exit 1
fi

echo "Opening ${latest}"
qlmanage -p "${latest}" >/dev/null 2>&1
