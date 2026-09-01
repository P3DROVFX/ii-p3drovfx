import socket
import threading
import json
import urllib.request
import ssl
import sys
import hashlib
import uuid
from pathlib import Path

PORT = 53317
MULTICAST_GROUP = "224.0.0.167"
# Client identity for the mTLS handshake used when probing devices. The
# official localsend-cli (see services/localsend_bridge.py) persists this
# device's certificate + private key as a single concatenated PEM; loading
# it here presents the shell's real identity/fingerprint during discovery
# instead of a throwaway one. Purely optional (servers don't require a
# client cert), so a missing file just leaves the context unauthenticated.
IDENTITY_FILE = Path.home() / ".config" / "localsend-cli" / "identity.pem"

# Configure SSL context with mTLS client certificate for LocalSend v2
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
if IDENTITY_FILE.exists():
    try:
        ctx.load_cert_chain(IDENTITY_FILE)
    except Exception:
        pass

def get_local_ip():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
        except Exception:
            return "127.0.0.1"

# Generate consistent fingerprint and device info
def get_device_info():
    hostname = socket.gethostname()
    fingerprint = ""
    if IDENTITY_FILE.exists():
        try:
            from cryptography.x509 import load_pem_x509_certificate
            from cryptography.hazmat.primitives import hashes
            # identity.pem concatenates the CERTIFICATE block followed by
            # the PRIVATE KEY block; only the certificate is needed here.
            pem_text = IDENTITY_FILE.read_text()
            cert_pem = pem_text[:pem_text.index("-----END CERTIFICATE-----") + len("-----END CERTIFICATE-----")]
            cert = load_pem_x509_certificate(cert_pem.encode())
            fingerprint = cert.fingerprint(hashes.SHA256()).hex()
        except Exception:
            pass
    if not fingerprint:
        fingerprint = hashlib.sha256(f"quickshell-{hostname}".encode()).hexdigest()

    return {
        "alias": f"quickshell@{hostname}",
        "version": "2.0",
        "deviceModel": "Linux",
        "deviceType": "desktop",
        "fingerprint": fingerprint,
        "port": PORT,
        "protocol": "https",
        "download": False,
    }

found_lock = threading.Lock()
discovered_ips = set()

def report_device(device):
    with found_lock:
        if device["ip"] not in discovered_ips:
            discovered_ips.add(device["ip"])
            print(json.dumps(device), flush=True)

# 1. Subnet unicast scan worker
def check_ip(ip, dev_info):
    try:
        # Quick TCP connection probe
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(1.0)
        result = s.connect_ex((ip, PORT))
        s.close()
        if result != 0:
            return
        
        # Port open! Send /register POST request
        url = f"https://{ip}:{PORT}/api/localsend/v2/register"
        data = json.dumps(dev_info).encode('utf-8')
        req = urllib.request.Request(
            url, 
            data=data, 
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, context=ctx, timeout=1.5) as response:
            res_data = json.loads(response.read().decode('utf-8'))
            if res_data:
                report_device({
                    "alias": res_data.get("alias", "?"),
                    "ip": ip,
                    "type": res_data.get("deviceType", "desktop"),
                    "model": res_data.get("deviceModel", "?"),
                    "download": res_data.get("download", False),
                    "port": PORT
                })
    except Exception:
        # Fallback to HTTP if HTTPS fails
        try:
            url = f"http://{ip}:{PORT}/api/localsend/v2/register"
            req = urllib.request.Request(
                url, 
                data=data, 
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=1.5) as response:
                res_data = json.loads(response.read().decode('utf-8'))
                if res_data:
                    report_device({
                        "alias": res_data.get("alias", "?"),
                        "ip": ip,
                        "type": res_data.get("deviceType", "desktop"),
                        "model": res_data.get("deviceModel", "?"),
                        "download": res_data.get("download", False),
                        "port": PORT
                    })
        except Exception:
            pass

def run_subnet_scan(dev_info):
    local_ip = get_local_ip()
    if local_ip == "127.0.0.1":
        return
    parts = local_ip.split(".")
    base_ip = ".".join(parts[:3])
    own_last = int(parts[3])
    
    threads = []
    for i in range(1, 255):
        if i == own_last:
            continue
        ip = f"{base_ip}.{i}"
        t = threading.Thread(target=check_ip, args=(ip, dev_info))
        t.start()
        threads.append(t)
    
    for t in threads:
        t.join()

# 2. UDP Multicast announcer and listener
def run_multicast_scan(dev_info):
    try:
        # Send announcement
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
        
        announce = {**dev_info, "announce": True}
        sock.sendto(json.dumps(announce).encode(), (MULTICAST_GROUP, PORT))
        sock.close()
    except Exception:
        pass

if __name__ == "__main__":
    dev_info = get_device_info()
    
    # Run multicast announcement in background
    m_thread = threading.Thread(target=run_multicast_scan, args=(dev_info,), daemon=True)
    m_thread.start()
    
    # Run high-speed subnet scan synchronously
    run_subnet_scan(dev_info)
