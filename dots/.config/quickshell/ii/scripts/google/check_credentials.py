#!/usr/bin/env python3
import json
import google_config

def main():
    print(json.dumps({
        "configured": google_config.has_credentials()
    }), flush=True)

if __name__ == "__main__":
    main()
