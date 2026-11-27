"""Report only expiration dates from the decoded profile and its pinned identity."""
from datetime import date, datetime, timezone
import os
import plistlib
import ssl
import subprocess
import sys


def report(label, expiry, today):
    days = (expiry - today).days
    message = f"{label} expires {expiry.isoformat()} ({days} days)"
    print(("::warning::" if days <= 75 else "") + message)


def main(profile_path):
    today = datetime.now(timezone.utc).date()
    with open(profile_path, "rb") as stream:
        profile = plistlib.load(stream)
    certificate, = profile["DeveloperCertificates"]
    end = subprocess.run(["openssl", "x509", "-inform", "DER", "-noout", "-enddate"],
                         input=certificate, stdout=subprocess.PIPE, check=True).stdout
    _, value = end.decode("ascii").strip().split("=", 1)
    cert_date = datetime.fromtimestamp(ssl.cert_time_to_seconds(value), timezone.utc).date()
    report("Distribution certificate", cert_date, today)
    report("Provisioning profile", profile["ExpirationDate"].date(), today)
    try:
        membership = date.fromisoformat(os.environ.get("APPLE_MEMBERSHIP_EXPIRY", ""))
    except ValueError:
        print("::notice::Check membership renewal in Apple Developer Membership details.")
    else:
        report("Recorded Apple membership", membership, today)


if __name__ == "__main__":
    main(sys.argv[1])
