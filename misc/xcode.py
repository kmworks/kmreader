#!/usr/bin/env python3
"""
Build and run script for KMReader.
Provides device selection with persistence.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple


def is_interactive() -> bool:
    """Check if running in an interactive terminal."""
    return sys.stdin.isatty() and sys.stdout.isatty()


class Color:
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    RED = "\033[0;31m"
    BLUE = "\033[0;34m"
    NC = "\033[0m"


# Off by default; the CAS cache is what lets separate checkouts (git worktrees) share compiled results
COMPILATION_CACHE_ARGS = ["COMPILATION_CACHE_ENABLE_CACHING=YES"]


class Device:
    def __init__(
        self, name: str, udid: str, state: str, platform: str, is_available: bool = True
    ):
        self.name = name
        self.udid = udid
        self.state = state
        self.platform = platform
        self.is_available = is_available

    def __repr__(self):
        status = f"({self.state})" if self.state else ""
        return f"{self.name} [{self.udid}] {status}"


class DeviceManager:
    DEVICES_FILE = "devices.json"

    def __init__(self):
        self.devices_file = Path(self.DEVICES_FILE)
        self.saved_devices = self._load_saved_devices()

    def _load_saved_devices(self) -> Dict[str, str]:
        """Load saved device preferences from JSON file."""
        if self.devices_file.exists():
            try:
                with open(self.devices_file, "r") as f:
                    return json.load(f)
            except (json.JSONDecodeError, IOError) as e:
                print(
                    f"{Color.YELLOW}Warning: Could not load {self.DEVICES_FILE}: {e}{Color.NC}"
                )
                return {}
        return {}

    def _save_devices(self):
        """Save device preferences to JSON file."""
        try:
            with open(self.devices_file, "w") as f:
                json.dump(self.saved_devices, f, indent=2)
        except IOError as e:
            print(
                f"{Color.YELLOW}Warning: Could not save {self.DEVICES_FILE}: {e}{Color.NC}"
            )

    def list_simulators(self, platform: str) -> List[Device]:
        """List available simulators for the given platform."""
        try:
            result = subprocess.run(
                ["xcrun", "simctl", "list", "devices", "--json"],
                capture_output=True,
                text=True,
                check=True,
            )
            data = json.loads(result.stdout)
            devices = []

            platform_filter = {
                "ios": "com.apple.CoreSimulator.SimRuntime.iOS",
                "tvos": "com.apple.CoreSimulator.SimRuntime.tvOS",
            }

            runtime_prefix = platform_filter.get(platform.lower())
            if not runtime_prefix:
                return devices

            for runtime, device_list in data["devices"].items():
                if runtime.startswith(runtime_prefix):
                    for device in device_list:
                        if device.get("isAvailable", False):
                            devices.append(
                                Device(
                                    name=device["name"],
                                    udid=device["udid"],
                                    state=device.get("state", ""),
                                    platform=platform,
                                    is_available=True,
                                )
                            )

            return devices
        except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError) as e:
            print(f"{Color.RED}Error listing simulators: {e}{Color.NC}")
            return []

    def list_physical_devices(self, platform: str) -> List[Device]:
        """List available physical devices for the given platform."""
        platform_aliases = {
            "ios": {"ios"},
            "tvos": {"tvos"},
        }

        target_platforms = platform_aliases.get(platform.lower())
        if not target_platforms:
            return []

        # Prefer CoreDevice JSON output, which is stable for scripting and works
        # regardless of the user-assigned device name.
        json_output_path: Optional[str] = None
        try:
            with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
                json_output_path = tmp.name

            subprocess.run(
                [
                    "xcrun",
                    "devicectl",
                    "list",
                    "devices",
                    "--json-output",
                    json_output_path,
                ],
                capture_output=True,
                text=True,
                check=True,
            )

            with open(json_output_path, "r") as f:
                payload = json.load(f)

            devices: List[Device] = []
            for item in payload.get("result", {}).get("devices", []):
                hardware = item.get("hardwareProperties", {})
                if hardware.get("reality") != "physical":
                    continue

                hardware_platform = str(hardware.get("platform", "")).lower()
                if hardware_platform not in target_platforms:
                    continue

                udid = hardware.get("udid")
                if not udid:
                    continue

                device_props = item.get("deviceProperties", {})
                connection_props = item.get("connectionProperties", {})

                name = device_props.get("name") or hardware.get("marketingName") or "Unknown Device"
                state = connection_props.get("tunnelState") or connection_props.get("pairingState") or ""

                devices.append(
                    Device(
                        name=name,
                        udid=udid,
                        state=state,
                        platform=platform,
                        is_available=True,
                    )
                )

            return devices
        except (subprocess.CalledProcessError, json.JSONDecodeError, IOError) as e:
            print(
                f"{Color.YELLOW}Warning: Could not list physical devices via devicectl: {e}{Color.NC}"
            )
        finally:
            if json_output_path and os.path.exists(json_output_path):
                try:
                    os.remove(json_output_path)
                except OSError:
                    pass

        # Fallback for older toolchains where devicectl is unavailable.
        try:
            result = subprocess.run(
                ["xcrun", "xctrace", "list", "devices"],
                capture_output=True,
                text=True,
                check=True,
            )

            devices = []
            platform_names = {
                "ios": "iPhone",
                "tvos": "Apple TV",
            }

            platform_name = platform_names.get(platform.lower())
            if not platform_name:
                return devices

            for line in result.stdout.split("\n"):
                line = line.strip()
                if "Simulator" in line:
                    continue
                if platform_name in line and "(" in line and ")" in line:
                    parts = line.rsplit("(", 1)
                    if len(parts) == 2:
                        name_part = parts[0].strip()
                        udid = parts[1].rstrip(")").strip()

                        if "(" in name_part:
                            name = name_part.rsplit("(", 1)[0].strip()
                        else:
                            name = name_part

                        devices.append(
                            Device(
                                name=name,
                                udid=udid,
                                state="",
                                platform=platform,
                                is_available=True,
                            )
                        )

            return devices
        except subprocess.CalledProcessError as e:
            print(
                f"{Color.YELLOW}Warning: Could not list physical devices: {e}{Color.NC}"
            )
            return []

    def get_device_key(self, platform: str, is_simulator: bool) -> str:
        """Generate key for storing device preference."""
        device_type = "simulator" if is_simulator else "device"
        return f"{platform.lower()}_{device_type}"

    def get_saved_device(self, platform: str, is_simulator: bool) -> Optional[str]:
        """Get saved device UDID for platform and type."""
        key = self.get_device_key(platform, is_simulator)
        return self.saved_devices.get(key)

    def save_device(self, platform: str, is_simulator: bool, udid: str):
        """Save device preference."""
        key = self.get_device_key(platform, is_simulator)
        self.saved_devices[key] = udid
        self._save_devices()

    def select_device(
        self,
        platform: str,
        is_simulator: bool,
        device_arg: Optional[str] = None,
        force_select: bool = False,
    ) -> Optional[str]:
        """
        Select a device interactively or from saved preferences.
        In non-interactive mode, automatically selects the first available device.

        Args:
            platform: Target platform (ios, tvos)
            is_simulator: Whether to select simulator or physical device
            device_arg: Optional specific device name or UDID
            force_select: If True, always show selection prompt even if saved device exists

        Returns device UDID or None if selection failed.
        """
        # List available devices
        if is_simulator:
            devices = self.list_simulators(platform)
            device_type_name = "simulator"
        else:
            devices = self.list_physical_devices(platform)
            device_type_name = "device"

        if not devices:
            print(f"{Color.RED}No {platform} {device_type_name}s found{Color.NC}")
            return None

        # If device specified by argument, try to find it
        if device_arg:
            for device in devices:
                if device_arg in (device.name, device.udid):
                    return device.udid
            print(f"{Color.YELLOW}Device '{device_arg}' not found{Color.NC}")

        # Check for saved device (skip if force_select is True)
        if not force_select:
            saved_udid = self.get_saved_device(platform, is_simulator)
            if saved_udid:
                for device in devices:
                    if device.udid == saved_udid:
                        print(
                            f"{Color.GREEN}Using saved {device_type_name}: {device.name}{Color.NC}"
                        )
                        return device.udid
                print(
                    f"{Color.YELLOW}Saved {device_type_name} no longer available{Color.NC}"
                )

        # Check if running in interactive mode
        interactive = is_interactive()
        mode_indicator = f"{Color.BLUE}[{'Interactive' if interactive else 'Non-interactive'} mode]{Color.NC}"

        # Non-interactive mode: automatically select first device
        if not interactive:
            selected = devices[0]
            print(f"{mode_indicator}")
            print(
                f"{Color.GREEN}Auto-selecting {device_type_name}: {selected.name}{Color.NC}"
            )
            # Save as default in non-interactive mode
            self.save_device(platform, is_simulator, selected.udid)
            return selected.udid

        # Interactive selection
        print(f"{mode_indicator}")
        print(
            f"\n{Color.BLUE}Available {platform.upper()} {device_type_name}s:{Color.NC}"
        )
        for i, device in enumerate(devices, 1):
            print(f"  {i}. {device}")

        while True:
            try:
                choice = input(
                    f"\n{Color.BLUE}Select {device_type_name} (1-{len(devices)}) or 'q' to quit: {Color.NC}"
                ).strip()

                if choice.lower() == "q":
                    return None

                index = int(choice) - 1
                if 0 <= index < len(devices):
                    selected = devices[index]

                    # Ask if user wants to save this choice
                    save_choice = (
                        input(
                            f"{Color.BLUE}Save this as default {device_type_name}? (y/n): {Color.NC}"
                        )
                        .strip()
                        .lower()
                    )
                    if save_choice == "y":
                        self.save_device(platform, is_simulator, selected.udid)
                        print(f"{Color.GREEN}Saved as default{Color.NC}")

                    return selected.udid
                else:
                    print(f"{Color.RED}Invalid selection{Color.NC}")
            except (ValueError, KeyboardInterrupt):
                print(f"\n{Color.YELLOW}Selection cancelled{Color.NC}")
                return None


class BuildRunner:
    def __init__(self, scheme: str = "KMReader", project: str = "KMReader.xcodeproj"):
        self.scheme = scheme
        project_path = Path(project)
        if project_path.is_absolute():
            self.project = str(project_path)
        elif project_path.exists():
            self.project = str(project_path.resolve())
        else:
            repo_root = Path(__file__).resolve().parent.parent
            self.project = str((repo_root / project).resolve())
        self.device_manager = DeviceManager()

    @staticmethod
    def _is_ci_environment() -> bool:
        """Detect whether current process is running in CI."""
        ci_value = os.getenv("CI", "").strip().lower()
        return ci_value in ("1", "true", "yes")

    def _validation_args(self, ci_mode: bool) -> List[str]:
        """Return xcodebuild validation flags for non-interactive CI runs."""
        if ci_mode or self._is_ci_environment():
            return ["-skipMacroValidation", "-skipPackagePluginValidation"]
        return []

    @staticmethod
    def _auth_args() -> List[str]:
        """Return authentication arguments for App Store Connect API key."""
        key_path = os.getenv("APP_STORE_CONNECT_API_KEY_PATH", "").strip()
        key_id = os.getenv("APP_STORE_CONNECT_API_KEY_ID", "").strip()
        issuer_id = os.getenv("APP_STORE_CONNECT_API_ISSUER_ID", "").strip()

        if key_path and key_id and issuer_id:
            print(f"{Color.GREEN}Using App Store Connect API key for authentication{Color.NC}")
            return [
                "-authenticationKeyPath",
                key_path,
                "-authenticationKeyID",
                key_id,
                "-authenticationKeyIssuerID",
                issuer_id,
            ]

        if any([key_path, key_id, issuer_id]):
            print(
                f"{Color.YELLOW}Warning: Incomplete App Store Connect API key configuration; skipping authentication arguments{Color.NC}"
            )
        return []

    @staticmethod
    def _load_env_if_present(script_dir: Path, project_root: Path) -> None:
        """Load environment variables from .env if available."""
        candidates = [project_root / ".env", script_dir / ".env"]
        for env_file in candidates:
            if not env_file.exists() or not env_file.is_file():
                continue

            print(f"{Color.GREEN}Loading environment variables from .env file...{Color.NC}")
            for raw_line in env_file.read_text(encoding="utf-8").splitlines():
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("export "):
                    line = line[len("export "):].strip()
                if "=" not in line:
                    continue

                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip()
                if not key:
                    continue

                if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
                    value = value[1:-1]
                os.environ[key] = value
            return

    @staticmethod
    def _platform_normalized(platform: str) -> Optional[str]:
        """Normalize platform label to canonical key."""
        value = platform.strip().lower()
        aliases = {
            "ios": "ios",
            "macos": "macos",
            "osx": "macos",
            "tvos": "tvos",
            "appletvos": "tvos",
        }
        return aliases.get(value)

    @staticmethod
    def _platform_display(platform: str) -> str:
        """Return display name for platform key."""
        mapping = {"ios": "iOS", "macos": "macOS", "tvos": "tvOS"}
        return mapping.get(platform, platform)

    @staticmethod
    def _platform_upload_type(platform: str) -> str:
        """Return altool upload type for platform key."""
        mapping = {"ios": "ios", "macos": "macos", "tvos": "appletvos"}
        return mapping.get(platform, "ios")

    @staticmethod
    def _generic_simulator_destination(platform: str) -> str:
        """Return a generic simulator destination for build-only actions."""
        mapping = {
            "ios": "generic/platform=iOS Simulator",
            "tvos": "generic/platform=tvOS Simulator",
        }
        return mapping[platform]

    def _archive_internal(
        self,
        platform: str,
        destination_dir: str = "archives",
        show_in_organizer: bool = False,
        ci_mode: bool = False,
    ) -> Tuple[bool, Optional[Path]]:
        """Archive app and return success flag and archive path."""
        normalized = self._platform_normalized(platform)
        archive_targets = {
            "ios": ("generic/platform=iOS", "KMReader-iOS"),
            "macos": ("platform=macOS", "KMReader-macOS"),
            "tvos": ("generic/platform=tvOS", "KMReader-tvOS"),
        }

        target = archive_targets.get(normalized or "")
        if not target:
            print(f"{Color.RED}Unknown platform: {platform}{Color.NC}")
            return False, None

        destination, archive_name = target
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

        if show_in_organizer:
            archive_root = (
                Path.home()
                / "Library/Developer/Xcode/Archives"
                / datetime.now().strftime("%Y-%m-%d")
            )
            print(
                f"{Color.YELLOW}Note: Archive will be saved to Xcode's default location and appear in Organizer{Color.NC}"
            )
        else:
            archive_root = Path(destination_dir).expanduser()

        archive_root.mkdir(parents=True, exist_ok=True)
        archive_path = archive_root / f"{archive_name}_{timestamp}.xcarchive"

        print(f"{Color.GREEN}Starting archive for {normalized}...{Color.NC}")
        print(f"Scheme: {self.scheme}")
        print(f"Destination: {destination}")
        print(f"Archive path: {archive_path}")
        print("")

        validation_args = self._validation_args(ci_mode)
        if validation_args:
            print(
                f"{Color.YELLOW}CI detected: skipping macro/plugin validation{Color.NC}"
            )

        auth_args = self._auth_args()

        print(f"{Color.YELLOW}Cleaning build folder...{Color.NC}")
        clean_cmd = [
            "xcodebuild",
            "clean",
            "-project",
            self.project,
            "-scheme",
            self.scheme,
            "-configuration",
            "Release",
            "-destination",
            destination,
            "-quiet",
        ]
        clean_cmd.extend(validation_args)
        clean_cmd.extend(auth_args)

        print(f"{Color.YELLOW}Archiving...{Color.NC}")
        archive_cmd = [
            "xcodebuild",
            "archive",
            "-project",
            self.project,
            "-scheme",
            self.scheme,
            "-configuration",
            "Release",
            "-destination",
            destination,
            "-archivePath",
            str(archive_path),
            "-quiet",
        ]
        archive_cmd.extend(validation_args)
        archive_cmd.extend(auth_args)
        archive_cmd.extend(COMPILATION_CACHE_ARGS)

        try:
            subprocess.run(clean_cmd, check=True)
            subprocess.run(archive_cmd, check=True)
            print(f"{Color.GREEN}✓ Archive created successfully!{Color.NC}")
            print(f"Archive location: {archive_path}")
            if show_in_organizer:
                print("")
                print(
                    "Archive is now available in Xcode Organizer (Window > Organizer)"
                )
            return True, archive_path
        except subprocess.CalledProcessError as e:
            print(f"{Color.RED}✗ Archive failed: {e}{Color.NC}")
            return False, None

    def archive(
        self,
        platform: str,
        destination_dir: str = "archives",
        show_in_organizer: bool = False,
        ci_mode: bool = False,
    ) -> bool:
        """Archive app for the specified platform."""
        success, _ = self._archive_internal(
            platform,
            destination_dir=destination_dir,
            show_in_organizer=show_in_organizer,
            ci_mode=ci_mode,
        )
        return success

    def export(
        self,
        archive_path: str,
        export_options: Optional[str] = None,
        destination_dir: Optional[str] = None,
        keep_archive: bool = False,
        platform_label: Optional[str] = None,
        load_env: bool = True,
    ) -> bool:
        """Export an existing archive to IPA/PKG."""
        script_dir = Path(__file__).resolve().parent
        project_root = script_dir.parent
        if load_env:
            self._load_env_if_present(script_dir, project_root)

        archive_path = archive_path.strip()
        export_options = (export_options or "").strip() or str(script_dir / "exportOptions.plist")
        destination_dir = (destination_dir or "").strip() or str(project_root / "exports")

        archive = Path(archive_path).expanduser()
        export_options_path = Path(export_options).expanduser()
        destination = Path(destination_dir).expanduser()

        if not archive.exists() or not archive.is_dir():
            print(f"{Color.RED}Error: Archive not found at '{archive}'{Color.NC}")
            return False

        if not export_options_path.exists() or not export_options_path.is_file():
            print(
                f"{Color.RED}Error: Export options plist not found at '{export_options_path}'{Color.NC}"
            )
            return False

        destination.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        export_path = destination / f"export_{timestamp}"

        print(f"{Color.GREEN}Starting export...{Color.NC}")
        print(f"Archive: {archive}")
        print(f"Export options: {export_options_path}")
        print(f"Export path: {export_path}")
        print("")

        auth_args = self._auth_args()
        cmd = [
            "xcodebuild",
            "-exportArchive",
            "-archivePath",
            str(archive),
            "-exportPath",
            str(export_path),
            "-exportOptionsPlist",
            str(export_options_path),
            "-quiet",
        ]
        cmd.extend(auth_args)

        try:
            subprocess.run(cmd, check=True)
        except subprocess.CalledProcessError as e:
            print(f"{Color.RED}✗ Export failed: {e}{Color.NC}")
            return False

        if platform_label:
            for ext in ("ipa", "pkg"):
                for file in export_path.glob(f"*.{ext}"):
                    target = export_path / f"KMReader-{platform_label}.{ext}"
                    if file.name != target.name:
                        file.rename(target)
                        print(f"{Color.GREEN}Renamed {file.name} -> {target.name}{Color.NC}")

        print(f"{Color.GREEN}✓ Export completed successfully!{Color.NC}")
        print(f"Export location: {export_path}")

        exported_files = sorted(export_path.iterdir())
        if exported_files:
            print("Exported files:")
            for file in exported_files:
                size = file.stat().st_size
                print(f"  - {file.name} ({size} bytes)")

        if keep_archive:
            print(f"{Color.YELLOW}Archive kept at: {archive}{Color.NC}")
        else:
            shutil.rmtree(archive, ignore_errors=False)
            print(f"{Color.GREEN}✓ Archive deleted{Color.NC}")

        return True

    def upload(self, artifact_path: str, platform: str, load_env: bool = True) -> bool:
        """Upload exported artifact to App Store Connect."""
        script_dir = Path(__file__).resolve().parent
        project_root = script_dir.parent
        if load_env:
            self._load_env_if_present(script_dir, project_root)

        artifact = Path(artifact_path).expanduser()
        if not artifact.exists() or not artifact.is_file():
            print(f"{Color.RED}Artifact not found at '{artifact}'{Color.NC}")
            return False

        key_path = os.getenv("APP_STORE_CONNECT_API_KEY_PATH", "").strip()
        key_id = os.getenv("APP_STORE_CONNECT_API_KEY_ID", "").strip()
        issuer_id = os.getenv("APP_STORE_CONNECT_API_ISSUER_ID", "").strip()

        key_file = str(Path(key_path).expanduser()) if key_path else ""

        if not key_path:
            print(
                f"{Color.RED}Error: APP_STORE_CONNECT_API_KEY_PATH is required for upload{Color.NC}"
            )
            return False
        if not Path(key_file).exists():
            print(f"{Color.RED}Error: API key file not found at '{key_path}'{Color.NC}")
            return False
        if not key_id or not issuer_id:
            print(
                f"{Color.RED}Error: APP_STORE_CONNECT_API_KEY_ID and APP_STORE_CONNECT_API_ISSUER_ID are required for upload{Color.NC}"
            )
            return False

        normalized = self._platform_normalized(platform) or "ios"
        upload_type = self._platform_upload_type(normalized)
        print(f"Uploading {artifact} ({self._platform_display(normalized)}) to App Store Connect...")

        cmd = [
            "xcrun",
            "altool",
            "--upload-app",
            "-f",
            str(artifact),
            "-t",
            upload_type,
            "--api-key",
            key_id,
            "--api-issuer",
            issuer_id,
            "--p8-file-path",
            key_file,
        ]

        try:
            subprocess.run(cmd, check=True)
            print(f"{Color.GREEN}✓ Upload completed for {artifact}{Color.NC}")
            return True
        except subprocess.CalledProcessError as e:
            print(f"{Color.RED}✗ Upload failed: {e}{Color.NC}")
            return False

    def release(
        self,
        show_in_organizer: bool = False,
        skip_export: bool = False,
        platform: Optional[str] = None,
    ) -> bool:
        """Archive/export/upload for platforms."""
        script_dir = Path(__file__).resolve().parent
        project_root = script_dir.parent
        self._load_env_if_present(script_dir, project_root)

        if platform:
            normalized = self._platform_normalized(platform)
            if not normalized:
                print(
                    f"{Color.RED}Error: Invalid platform '{platform}'. Must be ios, macos, or tvos.{Color.NC}"
                )
                return False
            platforms = [normalized]
        else:
            platforms = ["ios", "macos", "tvos"]

        archives_dir = project_root / "archives"
        exports_dir = project_root / "exports"
        export_options = {
            "ios": script_dir / "exportOptions.ios.plist",
            "macos": script_dir / "exportOptions.macos.plist",
            "tvos": script_dir / "exportOptions.tvos.plist",
        }

        if not skip_export:
            for key in platforms:
                plist = export_options[key]
                if not plist.exists():
                    print(
                        f"{Color.RED}Error: export options plist not found at '{plist}'{Color.NC}"
                    )
                    return False

        print(f"{Color.BLUE}========================================{Color.NC}")
        print(f"{Color.BLUE}KMReader - Release{Color.NC}")
        print(f"{Color.BLUE}========================================{Color.NC}")
        print("")
        print(f"{Color.GREEN}Step 1: Creating archives for all platforms...{Color.NC}")
        print("")

        archive_results: List[Tuple[str, Path]] = []
        archive_failed = False
        ci_mode = self._is_ci_environment()

        for key in platforms:
            print(f"{Color.YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{Color.NC}")
            print(f"{Color.YELLOW}Archiving for {key}...{Color.NC}")
            print(f"{Color.YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{Color.NC}")

            success, archive_path = self._archive_internal(
                key,
                destination_dir=str(archives_dir),
                show_in_organizer=show_in_organizer,
                ci_mode=ci_mode,
            )
            if not success or not archive_path:
                print(f"{Color.RED}✗ Archive failed for {key}!{Color.NC}")
                archive_failed = True
                print("")
                continue

            archive_results.append((key, archive_path))
            print(f"{Color.GREEN}✓ Archive saved: {archive_path}{Color.NC}")
            print("")

        if archive_failed:
            print(f"{Color.RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{Color.NC}")
            print(f"{Color.RED}✗ Some archives failed! Skipping export.{Color.NC}")
            print(f"{Color.RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{Color.NC}")
            return False

        print(f"{Color.GREEN}✓ All archives created successfully!{Color.NC}")
        print("")

        if skip_export:
            print(f"{Color.YELLOW}Skip export requested. Release process finished after archive.{Color.NC}")
            return True

        print(f"{Color.GREEN}Step 2: Exporting all archives...{Color.NC}")
        print("")

        for key, archive_path in archive_results:
            display_name = self._platform_display(key)
            print(f"{Color.YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{Color.NC}")
            print(f"{Color.YELLOW}Exporting {display_name} archive...{Color.NC}")
            print(f"{Color.YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{Color.NC}")

            success = self.export(
                str(archive_path),
                export_options=str(export_options[key]),
                destination_dir=str(exports_dir),
                keep_archive=True,
                platform_label=display_name,
                load_env=False,
            )
            if not success:
                return False
            print("")

        print(f"{Color.GREEN}✓ All exports completed successfully!{Color.NC}")
        print("")
        print(f"{Color.GREEN}Uploading exported builds...{Color.NC}")

        for key in platforms:
            display_name = self._platform_display(key)
            artifact_patterns = {
                "ios": ["KMReader-iOS.ipa", "*.ipa"],
                "macos": ["KMReader-macOS.pkg", "*.pkg"],
                "tvos": ["KMReader-tvOS.ipa", "*tvOS*.ipa"],
            }
            found: Optional[Path] = None

            for pattern in artifact_patterns[key]:
                candidates = sorted(exports_dir.rglob(pattern))
                if key == "ios":
                    candidates = [c for c in candidates if not c.name.endswith("tvOS.ipa")]
                if candidates:
                    found = candidates[-1]
                    break

            if not found:
                print(
                    f"{Color.YELLOW}No artifact found for {display_name}; skipping upload.{Color.NC}"
                )
                continue

            if not self.upload(str(found), key, load_env=False):
                return False

        print("")
        print(f"{Color.BLUE}========================================{Color.NC}")
        print(f"{Color.BLUE}Release Summary{Color.NC}")
        print(f"{Color.BLUE}========================================{Color.NC}")
        print("")
        print(f"{Color.GREEN}Archives created:{Color.NC}")
        for _, archive_path in archive_results:
            print(f"  - {archive_path}")
        print("")
        print(f"{Color.GREEN}Exports location:{Color.NC}")
        print(f"  - {exports_dir}")
        print("")
        print(f"{Color.GREEN}✓ Release process completed!{Color.NC}")
        return True

    def build(self, platform: str, ci_mode: bool = False) -> bool:
        """Build for the specified platform."""
        normalized = platform.lower()
        if normalized not in ("ios", "macos", "tvos"):
            print(f"{Color.RED}Unknown platform: {platform}{Color.NC}")
            return False

        # For iOS and tvOS, select simulator for building
        device_udid = None
        destination = None
        if normalized in ("ios", "tvos"):
            # Always use simulator for builds
            is_simulator = True
            device_udid = self.device_manager.select_device(platform, is_simulator)
            if device_udid:
                destination = f"id={device_udid}"
            else:
                destination = self._generic_simulator_destination(normalized)
                print(
                    f"{Color.YELLOW}No concrete {platform} simulator selected; using {destination}{Color.NC}"
                )
        elif normalized == "macos":
            destination = "platform=macOS"

        print(f"{Color.GREEN}Building for {platform.upper()}...{Color.NC}")

        # Do not force -sdk. Let destination drive platform selection, same as Xcode UI.
        cmd = [
            "xcodebuild",
            "-project",
            self.project,
            "-scheme",
            self.scheme,
            "build",
            "-quiet",
        ]
        cmd.extend(COMPILATION_CACHE_ARGS)

        if destination:
            cmd.extend(["-destination", destination])

        if ci_mode:
            cmd.extend(self._validation_args(ci_mode=True))
            cmd.extend(
                ["CODE_SIGN_IDENTITY=", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=NO"]
            )

        try:
            subprocess.run(cmd, check=True)
            print(f"{Color.GREEN}{platform.upper()} built successfully!{Color.NC}")
            return True
        except subprocess.CalledProcessError as e:
            print(f"{Color.RED}Build failed: {e}{Color.NC}")
            return False

    def run(
        self,
        platform: str,
        is_simulator: bool,
        device: Optional[str] = None,
        force_select: bool = False,
    ) -> bool:
        """Build and run on the specified platform and device."""
        if platform.lower() == "macos":
            return self._run_macos()

        # Select device
        device_udid = self.device_manager.select_device(
            platform, is_simulator, device, force_select
        )
        if not device_udid:
            print(f"{Color.RED}No device selected{Color.NC}")
            return False

        if is_simulator:
            return self._run_simulator(platform, device_udid)
        else:
            return self._run_device(platform, device_udid)

    def _run_macos(self) -> bool:
        """Build and run on macOS."""
        print(f"{Color.GREEN}Building and running on macOS...{Color.NC}")

        # Build first
        build_cmd = [
            "xcodebuild",
            "-project",
            self.project,
            "-scheme",
            self.scheme,
            "-destination",
            "platform=macOS",
            "build",
            "-quiet",
        ]
        build_cmd.extend(COMPILATION_CACHE_ARGS)

        try:
            subprocess.run(build_cmd, check=True)

            # Find the built app
            result = subprocess.run(
                build_cmd + ["-showBuildSettings"],
                capture_output=True,
                text=True,
                check=True,
            )

            app_path = None
            for line in result.stdout.split("\n"):
                if "BUILT_PRODUCTS_DIR" in line:
                    built_products_dir = line.split("=")[1].strip()
                    app_path = os.path.join(built_products_dir, f"{self.scheme}.app")
                    break

            if app_path and os.path.exists(app_path):
                print(f"{Color.GREEN}Launching {self.scheme}...{Color.NC}")
                subprocess.run(["open", app_path])
                return True
            else:
                print(f"{Color.RED}Could not find built app{Color.NC}")
                return False

        except subprocess.CalledProcessError as e:
            print(f"{Color.RED}Failed to build/run: {e}{Color.NC}")
            return False

    def _run_simulator(self, platform: str, device_udid: str) -> bool:
        """Build and run on simulator."""
        if platform.lower() not in ("ios", "tvos"):
            print(f"{Color.RED}Unknown platform: {platform}{Color.NC}")
            return False

        print(f"{Color.GREEN}Building for {platform.upper()} simulator...{Color.NC}")

        # Do not force -sdk. Let destination drive platform selection, same as Xcode UI.
        # Build
        build_cmd = [
            "xcodebuild",
            "-project",
            self.project,
            "-scheme",
            self.scheme,
            "-destination",
            f"id={device_udid}",
            "build",
            "-quiet",
        ]
        build_cmd.extend(COMPILATION_CACHE_ARGS)

        try:
            subprocess.run(build_cmd, check=True)

            # Get build settings to find app path
            result = subprocess.run(
                build_cmd + ["-showBuildSettings"],
                capture_output=True,
                text=True,
                check=True,
            )

            app_path = None
            for line in result.stdout.split("\n"):
                if "BUILT_PRODUCTS_DIR" in line:
                    built_products_dir = line.split("=")[1].strip()
                    app_path = os.path.join(built_products_dir, f"{self.scheme}.app")
                    break

            if not app_path or not os.path.exists(app_path):
                print(f"{Color.RED}Could not find built app{Color.NC}")
                return False

            # Boot simulator if needed
            print(f"{Color.GREEN}Booting simulator...{Color.NC}")
            subprocess.run(
                ["xcrun", "simctl", "boot", device_udid], stderr=subprocess.DEVNULL
            )  # Ignore error if already booted

            # Install app
            print(f"{Color.GREEN}Installing app...{Color.NC}")
            subprocess.run(
                ["xcrun", "simctl", "install", device_udid, app_path], check=True
            )

            # Get bundle identifier
            bundle_id = self._get_bundle_id(app_path)
            if not bundle_id:
                print(f"{Color.RED}Could not determine bundle identifier{Color.NC}")
                return False

            # Launch app
            print(f"{Color.GREEN}Launching app...{Color.NC}")
            subprocess.run(
                ["xcrun", "simctl", "launch", device_udid, bundle_id], check=True
            )

            print(f"{Color.GREEN}App launched successfully!{Color.NC}")
            return True

        except subprocess.CalledProcessError as e:
            print(f"{Color.RED}Failed to build/run: {e}{Color.NC}")
            return False

    def _run_device(self, platform: str, device_udid: str) -> bool:
        """Build and run on physical device."""
        if platform.lower() not in ("ios", "tvos"):
            print(f"{Color.RED}Unknown platform: {platform}{Color.NC}")
            return False

        print(
            f"{Color.GREEN}Building and installing on {platform.upper()} device...{Color.NC}"
        )

        # Do not force -sdk. Let destination drive platform selection, same as Xcode UI.
        # Build and install
        cmd = [
            "xcodebuild",
            "-project",
            self.project,
            "-scheme",
            self.scheme,
            "-destination",
            f"id={device_udid}",
            "build",
            "-quiet",
        ]
        cmd.extend(COMPILATION_CACHE_ARGS)

        try:
            subprocess.run(cmd, check=True)
            print(
                f"{Color.GREEN}App installed successfully! Launch it manually on your device.{Color.NC}"
            )
            return True
        except subprocess.CalledProcessError as e:
            print(f"{Color.RED}Failed to build/install: {e}{Color.NC}")
            return False

    def _get_bundle_id(self, app_path: str) -> Optional[str]:
        """Extract bundle identifier from app."""
        info_plist = os.path.join(app_path, "Info.plist")
        if not os.path.exists(info_plist):
            return None

        try:
            result = subprocess.run(
                ["defaults", "read", info_plist, "CFBundleIdentifier"],
                capture_output=True,
                text=True,
                check=True,
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError:
            return None


def main():
    parser = argparse.ArgumentParser(
        description="Build and run KMReader on various platforms",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    subparsers = parser.add_subparsers(dest="command", help="Command to execute")

    # Build command
    build_parser = subparsers.add_parser("build", help="Build for a platform")
    build_parser.add_argument(
        "platform", choices=["ios", "macos", "tvos"], help="Target platform"
    )
    build_parser.add_argument(
        "--ci", action="store_true", help="CI mode (no code signing)"
    )

    # Archive command
    archive_parser = subparsers.add_parser("archive", help="Archive for a platform")
    archive_parser.add_argument(
        "platform", choices=["ios", "macos", "tvos"], help="Target platform"
    )
    archive_parser.add_argument(
        "--destination",
        default="archives",
        help="Archive output directory (ignored with --show-in-organizer)",
    )
    archive_parser.add_argument(
        "--show-in-organizer",
        action="store_true",
        help="Save archive to Xcode Organizer location",
    )
    archive_parser.add_argument(
        "--ci",
        action="store_true",
        help="Enable CI-safe validation flags",
    )

    # Export command
    export_parser = subparsers.add_parser("export", help="Export archive")
    export_parser.add_argument("archive_path", help="Path to .xcarchive")
    export_parser.add_argument(
        "export_options",
        nargs="?",
        default=None,
        help="Export options plist path (default: misc/exportOptions.plist)",
    )
    export_parser.add_argument(
        "destination",
        nargs="?",
        default=None,
        help="Export output directory (default: ./exports)",
    )
    export_parser.add_argument(
        "--keep-archive",
        action="store_true",
        help="Keep archive after export",
    )
    export_parser.add_argument(
        "--platform",
        dest="platform_label",
        default=None,
        help="Platform label used to rename exported files (iOS/macOS/tvOS)",
    )

    # Upload command
    upload_parser = subparsers.add_parser("upload", help="Upload exported artifact")
    upload_parser.add_argument("artifact_path", help="Path to IPA/PKG artifact")
    upload_parser.add_argument(
        "platform", help="Platform label (ios/macos/tvos)"
    )

    # Release command
    release_parser = subparsers.add_parser(
        "release", help="Archive/export/upload for platforms"
    )
    release_parser.add_argument(
        "--show-in-organizer",
        action="store_true",
        help="Save archives to Xcode Organizer location",
    )
    release_parser.add_argument(
        "--skip-export",
        action="store_true",
        help="Only create archives; skip export and upload",
    )
    release_parser.add_argument(
        "--platform",
        choices=["ios", "macos", "tvos"],
        default=None,
        help="Process a single platform",
    )

    # Run command
    run_parser = subparsers.add_parser("run", help="Build and run on a device")
    run_parser.add_argument(
        "platform", choices=["ios", "macos", "tvos"], help="Target platform"
    )
    run_parser.add_argument(
        "--simulator",
        action="store_true",
        help="Run on simulator (default for iOS/tvOS)",
    )
    run_parser.add_argument(
        "--device", action="store_true", help="Run on physical device"
    )
    run_parser.add_argument("--target", help="Specific device name or UDID")
    run_parser.add_argument(
        "--select",
        action="store_true",
        help="Force device selection prompt even if saved device exists",
    )

    # List devices command
    list_parser = subparsers.add_parser("list", help="List available devices")
    list_parser.add_argument(
        "platform",
        nargs="?",
        choices=["ios", "tvos"],
        help="Platform to list devices for",
    )
    list_parser.add_argument(
        "--simulators", action="store_true", help="List simulators only"
    )
    list_parser.add_argument(
        "--devices", action="store_true", help="List physical devices only"
    )

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 1

    runner = BuildRunner()

    if args.command == "build":
        success = runner.build(args.platform, args.ci)
        return 0 if success else 1

    elif args.command == "archive":
        success = runner.archive(
            args.platform,
            destination_dir=args.destination,
            show_in_organizer=args.show_in_organizer,
            ci_mode=args.ci,
        )
        return 0 if success else 1

    elif args.command == "export":
        success = runner.export(
            args.archive_path,
            export_options=args.export_options,
            destination_dir=args.destination,
            keep_archive=args.keep_archive,
            platform_label=args.platform_label,
        )
        return 0 if success else 1

    elif args.command == "upload":
        success = runner.upload(args.artifact_path, args.platform)
        return 0 if success else 1

    elif args.command == "release":
        success = runner.release(
            show_in_organizer=args.show_in_organizer,
            skip_export=args.skip_export,
            platform=args.platform,
        )
        return 0 if success else 1

    elif args.command == "run":
        if args.platform == "macos":
            success = runner.run("macos", False)
        else:
            # Default to simulator for iOS/tvOS unless --device is specified
            is_simulator = not args.device if args.device else True
            force_select = args.select if hasattr(args, "select") else False
            success = runner.run(args.platform, is_simulator, args.target, force_select)
        return 0 if success else 1

    elif args.command == "list":
        dm = DeviceManager()

        platforms = [args.platform] if args.platform else ["ios", "tvos"]
        show_sims = args.simulators or not args.devices
        show_devices = args.devices or not args.simulators

        for platform in platforms:
            if show_sims:
                print(f"\n{Color.BLUE}{platform.upper()} Simulators:{Color.NC}")
                sims = dm.list_simulators(platform)
                if sims:
                    for sim in sims:
                        print(f"  {sim}")
                else:
                    print(f"  {Color.YELLOW}No simulators found{Color.NC}")

            if show_devices:
                print(f"\n{Color.BLUE}{platform.upper()} Physical Devices:{Color.NC}")
                devices = dm.list_physical_devices(platform)
                if devices:
                    for device in devices:
                        print(f"  {device}")
                else:
                    print(f"  {Color.YELLOW}No physical devices found{Color.NC}")

        return 0

    return 1


if __name__ == "__main__":
    sys.exit(main())
