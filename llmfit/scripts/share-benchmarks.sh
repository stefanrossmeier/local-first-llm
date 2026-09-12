#!/usr/bin/env bash
set -euo pipefail

echo "This will submit pending llmfit benchmark measurements upstream."
echo
echo "llmfit will:"
echo "  1. authenticate with GitHub"
echo "  2. fork AlexsJones/llmfit if necessary"
echo "  3. commit pending benchmark files"
echo "  4. create or update a pull request"
echo
echo "Nothing is submitted until you confirm inside llmfit."
echo

llmfit bench --share
