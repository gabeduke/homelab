#!/usr/bin/env python3
"""
Unified CLI tool for managing RetroPie ROMs and configurations.
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import zipfile
from pathlib import Path


# System mappings for 1G1R collection
SYSTEM_ZIP_MAP = {
    "nes": "Nintendo - Nintendo Entertainment System (Headerless).zip",
    "snes": "Nintendo - Super Nintendo Entertainment System.zip",
    "gb": "Nintendo - Game Boy.zip",
    "gbc": "Nintendo - Game Boy Color.zip",
    "gba": "Nintendo - Game Boy Advance.zip",
    "n64": "Nintendo - Nintendo 64 (BigEndian).zip",
    "genesis": "Sega - Mega Drive - Genesis.zip",
    "mastersystem": "Sega - Master System - Mark III.zip",
    "gamegear": "Sega - Game Gear.zip",
    "atari2600": "Atari - 2600.zip",
}

SYSTEM_NAME_MAP = {
    "Nintendo - Nintendo Entertainment System (Headerless).zip": "NES",
    "Nintendo - Super Nintendo Entertainment System.zip": "SNES",
    "Nintendo - Game Boy.zip": "Game Boy",
    "Nintendo - Game Boy Color.zip": "Game Boy Color",
    "Nintendo - Game Boy Advance.zip": "Game Boy Advance",
    "Nintendo - Nintendo 64 (BigEndian).zip": "Nintendo 64",
    "Sega - Mega Drive - Genesis.zip": "Genesis",
    "Sega - Master System - Mark III.zip": "Master System",
    "Sega - Game Gear.zip": "Game Gear",
    "Atari - 2600.zip": "Atari 2600",
}


class RetroPieClient:
    """Client for interacting with RetroPie via SSH."""
    
    def __init__(self, host=None, user=None):
        self.host = host or os.getenv("RETROPIE_HOST", "retropie.local")
        self.user = user or os.getenv("RETROPIE_USER", "pi")
    
    def run_remote_command(self, command, force_tty=False):
        """Run a command on the remote host via SSH."""
        ssh_cmd = ["ssh"]
        if force_tty:
            ssh_cmd.append("-tt")
        ssh_cmd.extend(["-T", f"{self.user}@{self.host}", command])
        
        return subprocess.run(ssh_cmd, text=True, capture_output=True)
    
    def run_remote_python(self, script, force_tty=False):
        """Run a Python script on the remote host via base64-encoded SSH."""
        script_b64 = base64.b64encode(script.encode()).decode()
        cmd = f"python3 -c \"import base64, sys; exec(base64.b64decode('{script_b64}').decode())\""
        return self.run_remote_command(cmd, force_tty=force_tty)
    
    def list_roms(self, system=None):
        """List ROMs on RetroPie, optionally filtered by system."""
        if system:
            remote_script = f"""import os, sys
rom_dir = os.path.expanduser('~/RetroPie/roms/{system}')
if not os.path.isdir(rom_dir):
    print(f"ERROR: System '{system}' not found at {{rom_dir}}", file=sys.stderr)
    sys.exit(1)
print(f"=== {system} ===")
print()
rom_count = 0
for f in sorted(os.listdir(rom_dir)):
    if os.path.isfile(os.path.join(rom_dir, f)) and f not in ('gamelist.xml', '.', '..'):
        print(f"  {{f}}")
        rom_count += 1
print()
print(f"Total: {{rom_count}} ROM(s)")
"""
        else:
            remote_script = """import os
roms_base = os.path.expanduser('~/RetroPie/roms')
total_roms = 0
for system_dir in sorted(os.listdir(roms_base)):
    system_path = os.path.join(roms_base, system_dir)
    if os.path.isdir(system_path):
        rom_count = 0
        roms = []
        for f in os.listdir(system_path):
            if os.path.isfile(os.path.join(system_path, f)) and f not in ('gamelist.xml', '.', '..'):
                roms.append(f)
                rom_count += 1
        if rom_count > 0:
            print(f"=== {system_dir} ===")
            print()
            for rom in sorted(roms):
                print(f"  {rom}")
            print()
            print(f"Subtotal: {rom_count} ROM(s)")
            print()
            total_roms += rom_count
print("=" * 40)
print(f"TOTAL: {total_roms} ROM(s) across all systems")
print("=" * 40)
"""
        
        result = self.run_remote_python(remote_script)
        if result.returncode != 0:
            print(result.stderr, file=sys.stderr)
            sys.exit(1)
        print(result.stdout)
    
    def remove_roms(self, system, pattern, dry_run=False, yes=False):
        """Remove ROMs matching a pattern."""
        # If pattern doesn't contain glob chars, add wildcards
        if not any(c in pattern for c in '*?[]'):
            pattern = f"*{pattern}*"
        
        # Find matching ROMs
        pattern_json = json.dumps(pattern)
        find_script = f"""import os, sys, fnmatch, json
rom_dir = os.path.expanduser('~/RetroPie/roms/{system}')
pattern = json.loads('{pattern_json}')
if not os.path.isdir(rom_dir):
    print(f"ERROR: System '{system}' not found at {{rom_dir}}", file=sys.stderr)
    sys.exit(1)
os.chdir(rom_dir)
# Exclude save files, metadata files, and other non-ROM files
exclude_extensions = ('.srm', '.sav', '.state', '.state.auto')
exclude_files = ('gamelist.xml', '.', '..')
matches = []
for f in os.listdir('.'):
    if not os.path.isfile(f):
        continue
    if f in exclude_files:
        continue
    if f.lower().endswith(exclude_extensions):
        continue
    # Match against full filename or filename without extension
    f_lower = f.lower()
    name_no_ext = os.path.splitext(f)[0].lower()
    pattern_lower = pattern.lower()
    if fnmatch.fnmatch(f_lower, pattern_lower) or fnmatch.fnmatch(name_no_ext, pattern_lower):
        matches.append(f)
if not matches:
    # List available ROMs to help debug
    all_roms = [f for f in os.listdir('.') if os.path.isfile(f) and f not in exclude_files and not f.lower().endswith(exclude_extensions)]
    print(f"ERROR: No ROMs found matching: {{pattern}}", file=sys.stderr)
    if all_roms:
        print(f"Available ROMs in '{system}' ({{len(all_roms)}}):", file=sys.stderr)
        for rom in sorted(all_roms)[:10]:  # Show first 10
            print(f"  {{rom}}", file=sys.stderr)
        if len(all_roms) > 10:
            print(f"  ... and {{len(all_roms) - 10}} more", file=sys.stderr)
    else:
        print(f"No ROM files found in '{system}' directory", file=sys.stderr)
    sys.exit(1)
for m in sorted(matches):
    print(m)
"""
        
        result = self.run_remote_python(find_script)
        if result.returncode != 0:
            print(result.stderr, file=sys.stderr)
            sys.exit(1)
        
        matches = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
        
        print(f"System:  {system}")
        print(f"Pattern: {pattern}")
        print()
        print(f"Found {len(matches)} ROM(s):")
        for rom in matches:
            print(f"  - {rom}")
        print()
        
        if dry_run:
            print("DRY RUN - Nothing deleted.")
            return
        
        # Confirm deletion
        if not yes:
            if sys.stdin.isatty():
                confirm = input("Type 'yes' to confirm deletion: ")
                if confirm != "yes":
                    print("Cancelled.")
                    sys.exit(1)
            else:
                print("Refusing to delete without --yes when no TTY is available.", file=sys.stderr)
                sys.exit(1)
        
        # Delete ROMs
        rom_files_json = json.dumps(matches)
        delete_script = f"""import os, sys, json
rom_dir = os.path.expanduser('~/RetroPie/roms/{system}')
media_dir = os.path.expanduser('~/.emulationstation/downloaded_media/{system}')
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
        
        print("Deleting ROMs and associated media...")
        result = self.run_remote_python(delete_script, force_tty=(not dry_run and not yes))
        if result.returncode != 0:
            print(result.stderr, file=sys.stderr)
            sys.exit(1)
        print(result.stdout)
        print()
        print("Done. In EmulationStation: START → UI Settings → 'Reload Games List' to refresh.")
    
    def upload_roms(self, system, source):
        """Upload ROM files to RetroPie."""
        source_path = Path(source)
        if not source_path.exists():
            print(f"Error: Source file or directory does not exist: {source}", file=sys.stderr)
            sys.exit(1)
        
        print(f"Uploading to RetroPie ({self.host})...")
        print(f"  System: {system}")
        print(f"  Source: {source}")
        print()
        
        # Create the system directory if it doesn't exist
        self.run_remote_command(f"mkdir -p ~/RetroPie/roms/{system}")
        
        # Upload the ROM(s)
        dest = f"{self.user}@{self.host}:~/RetroPie/roms/{system}/"
        if source_path.is_dir():
            print("Uploading directory contents...")
            subprocess.run(["scp", "-r", f"{source}/*", dest], check=True)
        else:
            print("Uploading file...")
            subprocess.run(["scp", str(source_path), dest], check=True)
        
        print()
        print("Upload complete!")
        print("You may need to restart EmulationStation to see the new games.")
        print(f"  ssh {self.user}@{self.host} 'sudo systemctl restart emulationstation'")


def find_rom_collection_dir():
    """Find the ROM collection directory."""
    script_dir = Path(__file__).parent
    repo_dir = script_dir.parent / "roms" / "proper1g1r-collection" / "ROMs"
    if repo_dir.exists() and any(repo_dir.iterdir()):
        return repo_dir
    downloads_dir = Path.home() / "Downloads" / "proper1g1r-collection" / "ROMs"
    if downloads_dir.exists():
        return downloads_dir
    return None


def search_collection(search_term, system_filter=None):
    """Search the 1G1R ROM collection."""
    collection_dir = find_rom_collection_dir()
    if not collection_dir:
        print("Error: ROM collection directory not found.", file=sys.stderr)
        print("", file=sys.stderr)
        print("The 1G1R ROM collection should be placed in:", file=sys.stderr)
        print("  devices/retropie/roms/proper1g1r-collection/ROMs/", file=sys.stderr)
        print("  or", file=sys.stderr)
        print("  ~/Downloads/proper1g1r-collection/ROMs/", file=sys.stderr)
        sys.exit(1)
    
    print(f"Searching for: '{search_term}'")
    print()
    
    total_matches = 0
    
    if system_filter and system_filter != "all":
        # Search specific system
        zip_file = SYSTEM_ZIP_MAP.get(system_filter)
        if not zip_file:
            print(f"Error: Unknown system '{system_filter}'", file=sys.stderr)
            sys.exit(1)
        
        zip_path = collection_dir / zip_file
        if not zip_path.exists():
            print(f"Error: ROM archive not found: {zip_path}", file=sys.stderr)
            sys.exit(1)
        
        system_name = SYSTEM_NAME_MAP.get(zip_file, system_filter)
        print(f"Searching in: {system_name}")
        print()
        
        with zipfile.ZipFile(zip_path, 'r') as zf:
            matches = [name for name in zf.namelist() if search_term.lower() in name.lower()]
            if matches:
                for match in sorted(matches):
                    print(f"  {match}")
                print()
                total_matches = len(matches)
    else:
        # Search all systems
        for zip_file in sorted(collection_dir.glob("*.zip")):
            zip_name = zip_file.name
            system_name = SYSTEM_NAME_MAP.get(zip_name, zip_name)
            
            with zipfile.ZipFile(zip_file, 'r') as zf:
                matches = [name for name in zf.namelist() if search_term.lower() in name.lower()]
                if matches:
                    print(f"=== {system_name} ===")
                    print()
                    for match in sorted(matches):
                        print(f"  {match}")
                    print()
                    total_matches += len(matches)
    
    if total_matches == 0:
        print(f"No games found matching: '{search_term}'")
        print()
        print("Try broader search terms or check spelling")
    else:
        print("=" * 42)
        print(f"Found {total_matches} game(s) matching '{search_term}'")
        print("=" * 42)
        print()
        print("To upload these games, use:")
        print(f"  retropie.py upload <system> <rom-file>")


def main():
    parser = argparse.ArgumentParser(
        description="Unified CLI tool for managing RetroPie",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--host", default=os.getenv("RETROPIE_HOST", "retropie.local"),
                       help="RetroPie hostname (default: retropie.local or RETROPIE_HOST env var)")
    parser.add_argument("--user", default=os.getenv("RETROPIE_USER", "pi"),
                       help="SSH user (default: pi or RETROPIE_USER env var)")
    
    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    
    # List command
    list_parser = subparsers.add_parser("list", help="List ROMs on RetroPie")
    list_parser.add_argument("system", nargs="?", help="System name (optional, lists all if omitted)")
    
    # Remove command
    remove_parser = subparsers.add_parser("remove", help="Remove ROMs from RetroPie")
    remove_parser.add_argument("system", help="System name (e.g., snes, nes, gba)")
    remove_parser.add_argument("pattern", help="Pattern to match ROM filenames (supports wildcards)")
    remove_parser.add_argument("--dry-run", action="store_true", help="Show what would be deleted without deleting")
    remove_parser.add_argument("--yes", action="store_true", help="Skip confirmation prompt")
    
    # Upload command
    upload_parser = subparsers.add_parser("upload", help="Upload ROMs to RetroPie")
    upload_parser.add_argument("system", help="System name (e.g., nes, snes, gba)")
    upload_parser.add_argument("source", help="Source file or directory to upload")
    
    # Search command
    search_parser = subparsers.add_parser("search", help="Search the 1G1R ROM collection")
    search_parser.add_argument("term", help="Search term")
    search_parser.add_argument("system", nargs="?", default="all",
                              help="System filter (optional, default: all)")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    if args.command == "search":
        search_collection(args.term, args.system)
    else:
        client = RetroPieClient(host=args.host, user=args.user)
        
        if args.command == "list":
            client.list_roms(args.system)
        elif args.command == "remove":
            if args.dry_run:
                print("DRY RUN MODE - No files will be deleted")
                print()
            client.remove_roms(args.system, args.pattern, dry_run=args.dry_run, yes=args.yes)
        elif args.command == "upload":
            client.upload_roms(args.system, args.source)


if __name__ == "__main__":
    main()

