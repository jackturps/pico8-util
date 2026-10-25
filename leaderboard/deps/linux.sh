#!/usr/bin/env bash
set -euo pipefail

if ! command -v npm >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y nodejs npm
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y nodejs npm
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm nodejs npm
  else
    exit 1
  fi
fi

if [ -w "$(npm prefix -g)" ]; then
  npm install -g wrangler@latest
else
  sudo npm install -g wrangler@latest
fi

if ! grep -q "You are logged in" <<<"$(wrangler whoami 2>&1)"; then
  wrangler login
fi
