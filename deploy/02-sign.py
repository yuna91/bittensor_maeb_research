#!/usr/bin/env python3
"""Sign a BeamCore registration message with a Bittensor hotkey.

BeamCore's first-time registration endpoints are unauthenticated and instead require an
sr25519 signature from the hotkey:

    orchestrator:  "{hotkey_ss58}:{fee_percentage}"
    worker:        "{hotkey_ss58}:{public_ip}:{port}"

Usage:
    ./02-sign.py --wallet <coldkey> --hotkey <hotkey> --message '5F...:10'
    ./02-sign.py --wallet <coldkey> --hotkey <hotkey> --ss58-only

Prints the 0x-prefixed signature on stdout (or the ss58 address with --ss58-only), so it can
be captured directly:  SIG=$(./02-sign.py ... )

Requires: pip install bittensor   (or bittensor-wallet)
"""
import argparse
import sys


def load_wallet(name: str, hotkey: str):
    """Support both the modern bittensor-wallet package and the legacy bittensor factory."""
    try:
        from bittensor_wallet import Wallet  # bittensor >= 8
        return Wallet(name=name, hotkey=hotkey)
    except ImportError:
        pass
    try:
        import bittensor as bt  # legacy
        return bt.wallet(name=name, hotkey=hotkey)
    except ImportError:
        sys.exit("ERROR: neither 'bittensor_wallet' nor 'bittensor' is installed.\n"
                 "       pip install bittensor")


def main() -> None:
    p = argparse.ArgumentParser(description="Sign a BeamCore registration message.")
    p.add_argument("--wallet", required=True, help="coldkey / wallet name")
    p.add_argument("--hotkey", required=True, help="hotkey name")
    p.add_argument("--message", help="exact message to sign")
    p.add_argument("--ss58-only", action="store_true", help="print the hotkey ss58 address and exit")
    p.add_argument("--coldkeypub-only", action="store_true",
                   help="print the coldkey public ss58 address and exit (no password needed)")
    args = p.parse_args()

    if not args.message and not (args.ss58_only or args.coldkeypub_only):
        p.error("--message is required unless --ss58-only or --coldkeypub-only is given")

    wallet = load_wallet(args.wallet, args.hotkey)

    if args.coldkeypub_only:
        # coldkeypub is the public half only — never prompts for the coldkey password.
        try:
            print(wallet.coldkeypub.ss58_address)
        except Exception as exc:  # noqa: BLE001
            sys.exit(f"ERROR: could not read coldkeypub for wallet '{args.wallet}': {exc}")
        return

    try:
        keypair = wallet.hotkey
    except Exception as exc:  # noqa: BLE001 - surface the real cause to the operator
        sys.exit(f"ERROR: could not load hotkey '{args.hotkey}' in wallet '{args.wallet}': {exc}")

    if args.ss58_only:
        print(keypair.ss58_address)
        return

    # The hotkey is normally unencrypted; the coldkey is the protected one.
    signature = keypair.sign(args.message.encode("utf-8"))
    print("0x" + signature.hex())


if __name__ == "__main__":
    main()
