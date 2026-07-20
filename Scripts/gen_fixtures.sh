#!/bin/bash
# Synthesizes dictation-like WAVs (16 kHz mono) with macOS TTS - micless E2E audio.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Fixtures /tmp/gw_fixtures

gen() {
  say -v Samantha -o "/tmp/gw_fixtures/$1.aiff" "$2"
  afconvert -f WAVE -d LEI16@16000 -c 1 "/tmp/gw_fixtures/$1.aiff" "Fixtures/$1.wav"
  echo "Fixtures/$1.wav"
}

gen basic "Um, so basically I want you to, uh, refactor the login page and, um, make the button blue."
gen correction "Send the invoice on Tuesday. No wait, send it on Wednesday morning."
gen technical "Open ghostwriter dot swift and add a function called handle hotkey that calls the transcription service."
gen vibecoding "Add a use effect hook that fetches the user profile from supabase and, um, put a loading spinner while it waits."
