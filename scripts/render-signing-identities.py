#!/usr/bin/env python3
"""Render a private signing keychain from credential-manager injected secrets."""
import base64
import hashlib
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
keychain = root / '_local' / 'signing.keychain-db'
keychain.parent.mkdir(parents=True, exist_ok=True)
password = os.environ['PAD_KEYCHAIN_PASSWORD']

def run(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(f'{args[0]} failed: {result.stderr.replace(password, "[redacted]").strip()}')
    return result.stdout

if not keychain.exists():
    run('security', 'create-keychain', '-p', password, str(keychain))
run('security', 'unlock-keychain', '-p', password, str(keychain))
run('security', 'set-keychain-settings', '-lut', '21600', str(keychain))
# Import the intermediate without overriding system trust decisions.
with tempfile.TemporaryDirectory(prefix='pad-ca-') as temp:
    intermediate = str(Path(temp) / 'wwdr.cer')
    run('curl', '-fsSL', 'https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer', '-o', intermediate)
    digest = hashlib.sha1(Path(intermediate).read_bytes()).hexdigest().upper()
    if digest not in run('security', 'find-certificate', '-a', '-Z', str(keychain)):
        run('security', 'import', intermediate, '-k', str(keychain))
with tempfile.TemporaryDirectory(prefix='pad-signing-') as temp:
    folder = Path(temp)
    for name in ['development', 'application', 'installer']:
        prefix = 'PAD_' + name.upper()
        key = folder / (name + '.key')
        cert = folder / (name + '.cer')
        pem = folder / (name + '.pem')
        p12 = folder / (name + '.p12')
        key.write_text(os.environ[prefix + '_PRIVATE_KEY'])
        key.chmod(0o600)
        cert.write_bytes(base64.b64decode(os.environ[prefix + '_CERTIFICATE']))
        digest = hashlib.sha1(cert.read_bytes()).hexdigest().upper()
        if digest in run('security', 'find-identity', '-p', 'basic', str(keychain)):
            continue
        run('openssl', 'x509', '-inform', 'DER', '-in', str(cert), '-out', str(pem))
        subprocess.run(['openssl', 'pkcs12', '-export', '-legacy', '-inkey', str(key), '-in', str(pem), '-out', str(p12), '-passout', 'stdin'], input=password+'\n', text=True, check=True, capture_output=True)
        run('security', 'import', str(p12), '-k', str(keychain), '-P', password, '-T', '/usr/bin/codesign', '-T', '/usr/bin/productbuild', '-T', '/usr/bin/security')
run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, str(keychain))
existing = shlex.split(run('security', 'list-keychains', '-d', 'user'))
if str(keychain) not in existing:
    run('security', 'list-keychains', '-d', 'user', '-s', *existing, str(keychain))
print('Rendered distribution and development identities into the private signing keychain.')
