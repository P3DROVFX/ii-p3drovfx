#!/usr/bin/env python3
"""Offer the other output on cards with separate speaker and headphone HiFi profiles."""

import json
import os
import subprocess
import sys
import time


def pactl(*args):
    return subprocess.check_output(
        ["pactl", *args], text=True, timeout=3, env={**os.environ, "LC_ALL": "C"}
    ).strip()


def objects(kind):
    return json.loads(pactl("-f", "json", "list", kind))


def alternates():
    sinks = objects("sinks")
    for card in objects("cards"):
        active = card["active_profile"]
        if not active or not active.startswith("HiFi ("):
            continue

        ports = card["ports"]
        active_ports = {name for name, port in ports.items() if active in port["profiles"]}
        for name, port in ports.items():
            kind = port["properties"].get("port.type")
            if kind not in ("speaker", "headphones") or name in active_ports:
                continue
            if port["availability"] == "not available":
                continue

            opposite = "headphones" if kind == "speaker" else "speaker"
            for profile in port["profiles"]:
                if not profile.startswith("HiFi (") or not card["profiles"][profile]["available"]:
                    continue
                new_ports = {key for key, value in ports.items() if profile in value["profiles"]}
                removed = active_ports - new_ports
                if new_ports - active_ports != {name} or len(removed) != 1:
                    continue
                active_port = removed.pop()
                if ports[active_port]["properties"].get("port.type") != opposite:
                    continue
                card_sinks = [sink for sink in sinks
                              if sink["properties"].get("device.id") == card["properties"]["object.id"]]
                # Real sink names, so the picker never guesses UCM naming.
                active_sink = next((sink["name"] for sink in card_sinks
                                    if sink.get("active_port") == active_port), None)
                yield {
                    "activeSink": active_sink,
                    "otherSinks": [sink["name"] for sink in card_sinks if sink["name"] != active_sink],
                    "card": card["name"],
                    "deviceId": card["properties"]["object.id"],
                    "port": name,
                    "profile": profile,
                    "previousProfile": active,
                    "type": kind,
                }
                break


def wait_for(find):
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        result = find()
        if result:
            return result
        time.sleep(0.05)
    raise RuntimeError("Timed out waiting for the audio output")


def switch(card, port, profile):
    choice = next((item for item in alternates()
                   if (item["card"], item["port"], item["profile"]) == (card, port, profile)), None)
    if choice is None:
        raise RuntimeError("The requested audio profile is no longer available")

    def find_sink():
        return next((sink["name"] for sink in objects("sinks")
                     if sink["properties"].get("device.id") == choice["deviceId"]
                     and sink.get("active_port") == port), None)

    previous_sink = pactl("get-default-sink")
    try:
        pactl("set-card-profile", card, profile)
        sink = wait_for(find_sink)
        pactl("set-default-sink", sink)
        wait_for(lambda: pactl("get-default-sink") == sink)
        return sink
    except (RuntimeError, subprocess.SubprocessError) as error:
        try:
            pactl("set-card-profile", card, choice["previousProfile"])
            wait_for(lambda: any(sink["name"] == previous_sink for sink in objects("sinks")))
            pactl("set-default-sink", previous_sink)
        except (RuntimeError, subprocess.SubprocessError) as rollback_error:
            raise RuntimeError(f"{error} (rollback failed: {rollback_error})") from error
        raise


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["list"]:
            print(json.dumps(list(alternates())))
        elif len(sys.argv) == 5 and sys.argv[1] == "switch":
            print(switch(*sys.argv[2:]))
        else:
            sys.exit("Usage: analog-output.py list | switch CARD PORT PROFILE")
    except (RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
