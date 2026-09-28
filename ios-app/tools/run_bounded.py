#!/usr/bin/env python3
"""Bound simulator CLI calls, including their child processes on macOS/Linux."""
import argparse
import os
import signal
import subprocess
import sys


def run(command, timeout):
    process = subprocess.Popen(command, start_new_session=os.name == "posix")
    try:
        return process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        print(f"Command timed out after {timeout}s: {command[0]}", file=sys.stderr, flush=True)
        if os.name == "posix":
            os.killpg(process.pid, signal.SIGKILL)
        else:
            process.kill()
        process.wait()
        return 124


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if args.timeout <= 0 or not command:
        parser.error("positive timeout and command required")
    raise SystemExit(run(command, args.timeout))
