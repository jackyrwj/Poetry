#!/bin/sh

set -eu

config_path="${CI_PRIMARY_REPOSITORY_PATH}/Poetry/AIConfig.plist"

if [ -z "${BAILIAN_API_KEY:-}" ]; then
    echo "error: BAILIAN_API_KEY is not configured in the Xcode Cloud workflow."
    exit 1
fi

mkdir -p "$(dirname "${config_path}")"
plutil -create xml1 "${config_path}"
plutil -insert endpoint -string "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions" "${config_path}"
plutil -insert model -string "qwen-plus" "${config_path}"
plutil -insert apiKey -string "${BAILIAN_API_KEY}" "${config_path}"

echo "Created Poetry/AIConfig.plist for the Xcode Cloud build."
