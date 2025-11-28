#!/usr/bin/env python3
"""
Remove ROMs from RetroPie by system and pattern matching.
"""

import argparse
import base64
import json
import os
import subprocess
import sys


def usage():
    print("Usage: remove-roms.py <system> '<pattern>' [--dry-run] [--yes]")
    print("Examples:")
    print("  remove-roms.py snes 'Zelda*' --dry-run")
    print("  remove-roms.py gba 'Pokemon - Emerald Version (USA, Europe).gba' --yes")


def run_remote_command(host, user, command, force_tty=False):
    """Run a command on the remote host via SSH."""
    ssh_cmd = ["ssh"]
    if force_tty:
        ssh_cmd.append("-tt")
    ssh_cmd.extend(["-T", f"{user}@{host}", command])
    
    return subprocess.run(ssh_cmd, text=True, capture_output=True)


def find_roms(host, user, system, pattern):
    """Find ROMs matching the pattern on the remote system."""
    rom_dir = f"~/RetroPie/roms/{system}"
    
    # Use base64 encoding to avoid shell quoting issues
    pattern_json = json.dumps(pattern)
    remote_script = f"""import os, sys, fnmatch, json
rom_dir = os.path.expanduser('{rom_dir}')
pattern = json.loads('{pattern_json}')
if not os.path.isdir(rom_dir):
    print(f"ERROR: System '{system}' not found at {{rom_dir}}", file=sys.stderr)
    sys.exit(1)
os.chdir(rom_dir)
matches = [f for f in os.listdir('.') if os.path.isfile(f) and fnmatch.fnmatch(f.lower(), pattern.lower())]
if not matches:
    print(f"ERROR: No ROMs found matching: {{pattern}}", file=sys.stderr)
    sys.exit(1)
for m in sorted(matches):
    print(m)
"""
    
    # Base64 encode to avoid quoting issues
    script_b64 = base64.b64encode(remote_script.encode()).decode()
    cmd = f"python3 -c \"import base64, sys; exec(base64.b64decode('{script_b64}').decode())\""
    
    result = run_remote_command(host, user, cmd)
    
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    
    return [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]


def delete_roms(host, user, system, rom_files, dry_run=False, yes=False):
    """Delete ROMs and associated media files."""
    rom_dir = f"~/RetroPie/roms/{system}"
    media_dir = f"~/.emulationstation/downloaded_media/{system}"
    
    # Build Python script to run remotely, using base64 to avoid quoting issues
    rom_files_json = json.dumps(rom_files)
    
    remote_script = f"""import os, sys, json
rom_dir = os.path.expanduser('{rom_dir}')
media_dir = os.path.expanduser('{media_dir}')
rom_files = json.loads('{rom_files_json}')
dry_run = {dry_run}
os.chdir(rom_dir)
deleted_roms, deleted_media = [], []
for rom_file in rom_files:
    rom_path = os.path.join(rom_dir, rom_file)
    if not os.path.isfile(rom_path):
        continue
    if not dry_run:
        os.remove(rom_path)
    deleted_roms.append(rom_file)
    print(f"  ROM: {{rom_file}}")
    if os.path.isdir(media_dir):
        name_no_ext = os.path.splitext(rom_file)[0]
        for media_file in os.listdir(media_dir):
            media_path = os.path.join(media_dir, media_file)
            if os.path.isfile(media_path):
                media_name_no_ext = os.path.splitext(media_file)[0]
                if media_name_no_ext.lower() == name_no_ext.lower():
                    if not dry_run:
                        os.remove(media_path)
                    deleted_media.append(media_file)
                    print(f"    media: {{media_file}}")
print(f"\\nDeleted {{len(deleted_roms)}} ROM(s) and {{len(deleted_media)}} media file(s)")
"""
    
    # Base64 encode to avoid quoting issues
    script_b64 = base64.b64encode(remote_script.encode()).decode()
    cmd = f"python3 -c \"import base64, sys; exec(base64.b64decode('{script_b64}').decode())\""
    
    result = run_remote_command(host, user, cmd, force_tty=(not dry_run and not yes))
    
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    
    print(result.stdout)


def main():
    parser = argparse.ArgumentParser(
        description="Remove ROMs from RetroPie by system and pattern",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s snes 'Zelda*' --dry-run
  %(prog)s gba 'Pokemon - Emerald Version (USA, Europe).gba' --yes
        """
    )
    parser.add_argument("system", help="System name (e.g., snes, nes, gba)")
    parser.add_argument("pattern", help="Pattern to match ROM filenames (supports wildcards)")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be deleted without deleting")
    parser.add_argument("--yes", action="store_true", help="Skip confirmation prompt")
    parser.add_argument("--host", default=os.getenv("RETROPIE_HOST", "retropie.local"),
                       help="RetroPie hostname (default: retropie.local or RETROPIE_HOST env var)")
    parser.add_argument("--user", default=os.getenv("RETROPIE_USER", "pi"),
                       help="SSH user (default: pi or RETROPIE_USER env var)")
    
    args = parser.parse_args()
    
    # If pattern doesn't contain glob chars, add wildcards
    pattern = args.pattern
    if not any(c in pattern for c in '*?[]'):
        pattern = f"*{pattern}*"
    
    if args.dry_run:
        print("DRY RUN MODE - No files will be deleted")
        print()
    
    print(f"System:  {args.system}")
    print(f"Pattern: {pattern}")
    print()
    
    # Find matching ROMs
    try:
        matches = find_roms(args.host, args.user, args.system, pattern)
    except Exception as e:
        print(f"Error finding ROMs: {e}", file=sys.stderr)
        sys.exit(1)
    
    print(f"Found {len(matches)} ROM(s):")
    for rom in matches:
        print(f"  - {rom}")
    print()
    
    if args.dry_run:
        print("DRY RUN - Nothing deleted.")
        return
    
    # Confirm deletion
    if not args.yes:
        if sys.stdin.isatty():
            confirm = input("Type 'yes' to confirm deletion: ")
            if confirm != "yes":
                print("Cancelled.")
                sys.exit(1)
        else:
            print("Refusing to delete without --yes when no TTY is available.", file=sys.stderr)
            sys.exit(1)
    
    print("Deleting ROMs and associated media...")
    try:
        delete_roms(args.host, args.user, args.system, matches, dry_run=False, yes=args.yes)
    except Exception as e:
        print(f"Error deleting ROMs: {e}", file=sys.stderr)
        sys.exit(1)
    
    print()
    print("Done. In EmulationStation: START → UI Settings → 'Reload Games List' to refresh.")


if __name__ == "__main__":
    main()

