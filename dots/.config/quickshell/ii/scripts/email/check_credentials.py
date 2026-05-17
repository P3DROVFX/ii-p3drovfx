#!/usr/bin/env python3
import json
import gmail_config

def main():
    print(json.dumps({
        "configured": gmail_config.has_credentials()
    }))

if __name__ == "__main__":
    main()
