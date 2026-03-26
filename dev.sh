#!/bin/bash
# VoiceFlow 开发模式 — 编译 + 重启
set -e

echo "Building..."
swift build 2>&1 | grep -E "error:|Build complete" || true

killall VoiceFlow 2>/dev/null && echo "Stopped old process" || true
sleep 0.3

echo "Starting VoiceFlow..."
nohup .build/debug/VoiceFlow > /dev/null 2>&1 &
echo "VoiceFlow running (PID $!)"
