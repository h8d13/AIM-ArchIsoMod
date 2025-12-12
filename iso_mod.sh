#!/bin/sh
#set -e

SCRIPT_DIR="$(dirname "$0")"
. "$SCRIPT_DIR/general.conf"
PROFILE_LIST="$SCRIPT_DIR/iso_profiles/$iso_profile.conf"

PROFILE_DIR="$SCRIPT_DIR/archiso_profile"
WORK_DIR="$SCRIPT_DIR/archiso_work"
OUTPUT_DIR="$SCRIPT_DIR/a"

silent_mode="${silent_mode:-0}"
build_date=$(date '+%Y.%m.%d')

# Check if running as root
[ "$(id -u)" -ne 0 ] && echo "Error: Must run as root" && exit 1

# Check for system updates
command -v checkupdates >/dev/null 2>&1 && [ -n "$(checkupdates 2>/dev/null)" ] && \
    echo "System has pending updates (sudo pacman -Syu recommended)"

# Cleanup function for trap
cleanup() {
    if [ -d "$PROFILE_DIR" ]; then
        echo "Cleaning up build directories..."
        rm -rf "$PROFILE_DIR"
    fi
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}
# Register cleanup on exit/interrupt
trap cleanup EXIT INT TERM

echo "Setting up archiso profile..."
#rm -rf "$PROFILE_DIR"
mkdir -p "$PROFILE_DIR"
echo "Creating airootfs..."
mkdir -p "$PROFILE_DIR/airootfs/root"

echo "Using RELENG profile default..."
# Use standard release engeneering profile (same as ISO)
cp -r /usr/share/archiso/configs/releng/* "$PROFILE_DIR"

# Customize ISO name in profiledef.sh
sed -i "s/^iso_name=.*/iso_name=\"$NAME\"/" "$PROFILE_DIR/profiledef.sh"

# Add git to ISO packages (needed for users to clone Vase)
echo "Adding git to ISO package list..."
echo "git" >> "$PROFILE_DIR/packages.x86_64"
echo "nano" >> "$PROFILE_DIR/packages.x86_64"
## Add more as needed

# Add git clone command to zsh history for easy access (arrow up once)
echo "Adding git clone to zsh history..."
cat > "$PROFILE_DIR/airootfs/root/.zsh_history" << HISTEOF
: 1728000000:0;pacman-key --init && git clone -b $installer_branch $installer_repo && cd $repo_name && python -m archinstall
HISTEOF

# Append custom MOTD
cat >> "$PROFILE_DIR/airootfs/etc/motd" << EOF

╔═══════════════════════════════════════╗
      $NAME ARCH INSTALLER ${rel_v}
      ISO Generated ${build_date}...
╚═══════════════════════════════════════╝
╔═══════════════════════════════════════╗
      Ethernet cable works out of box.
 iwctl station wlan0 connect "SSID"
      Where SSID is you WiFi...
╚═══════════════════════════════════════╝

╔═══════════════════════════════════════╗
    INSTALL: UP KEY ↑ then ENTER ╛ KEY
╚═══════════════════════════════════════╝
EOF

# Now this the cool part
if [ -f "$PROFILE_LIST" ]; then
    echo "Creating local package repository for $iso_profile packages..."

    # Read packages from profile (skip comments and empty lines)
    packages=$(grep -v '^#' "$PROFILE_LIST" | grep -v '^$' | tr '\n' ' ')

    if [ -n "$packages" ]; then
        # Create local repo directory in airootfs
        REPO_DIR="$PROFILE_DIR/airootfs/root/vase_packages"
        mkdir -p "$REPO_DIR"

        echo "Downloading packages with dependencies: $packages"

        # Download packages (pacman resolves dependencies automatically)
        if [ "$silent_mode" = "1" ]; then
            pacman -Sw --noconfirm $packages >/dev/null 2>&1
        else
            pacman -Sw --noconfirm $packages
        fi

        if [ $? -eq 0 ]; then
            # Recursively get ALL dependencies using pactree
            echo "Resolving complete dependency tree..."
            all_packages=$(
                for pkg in $packages; do
                    pactree -u -l "$pkg" 2>/dev/null || echo "$pkg"
                done | sort -u | grep -v "^$"
            )
            dep_count=$(echo "$all_packages" | wc -l)
            echo "Copying $dep_count packages to ISO repository..."

            # Copy all packages from cache
            {
                for pkg_name in $all_packages; do
                    latest=$(ls -t /var/cache/pacman/pkg/${pkg_name}-*.pkg.tar.zst 2>/dev/null | head -n1)
                    if [ -n "$latest" ]; then
                        cp "$latest" "$REPO_DIR/" 2>/dev/null || true
                    fi
                done
            } >/dev/null 2>&1

            # Create local repository database (using explicit file list)
            echo "Creating repository database..."
            if [ -n "$(ls -A "$REPO_DIR"/*.pkg.tar.zst 2>/dev/null)" ]; then
                repo-add "$REPO_DIR/vase_repo.db.tar.gz" "$REPO_DIR"/*.pkg.tar.zst >/dev/null 2>&1
            else
                echo "No packages found to add to repository"
            fi

            pkg_count=$(find "$REPO_DIR" -name "*.pkg.tar.zst" | wc -l)
            cache_size=$(du -sh "$REPO_DIR" | cut -f1)

            # Create pacman.conf in airootfs with custom repo FIRST (for live environment only)
            echo "Configuring pacman to use local repository with priority..."
            mkdir -p "$PROFILE_DIR/airootfs/etc"

            # Backup original pacman.conf to live ISO for fallback
            cp "$PROFILE_DIR/pacman.conf" "$PROFILE_DIR/airootfs/etc/pacman.conf.backup"

            # Insert vase_repo BEFORE [core] so it has priority on other sources !
            awk '
                /^\[core\]/ && !inserted {
                    print "# Local repository for pre-cached packages"
                    print "[local_repo]"
                    print "SigLevel = Optional TrustAll"
                    print "Server = file:///root/local_packages"
                    print ""
                    inserted=1
                }
                {print}
            ' "$PROFILE_DIR/pacman.conf" > "$PROFILE_DIR/airootfs/etc/pacman.conf"

            # Apply pacman styling enable Color and ILoveCandy
            echo "Styling pacman.conf (Color + ILoveCandy)..."
            PACMAN_CONF="$PROFILE_DIR/airootfs/etc/pacman.conf"

            # Enable Color if commented
            sed -i 's/^#Color$/Color/' "$PACMAN_CONF"

            # Add ILoveCandy after "# Misc options" if not already present
            if ! grep -q "ILoveCandy" "$PACMAN_CONF"; then
                sed -i '/^# Misc options$/a ILoveCandy' "$PACMAN_CONF"
            fi

            echo "Created local repo with $pkg_count packages ($cache_size) for installation"
        else
            echo "Failed to download packages, continuing without cache"
        fi
    fi
else
    echo "No profile found at $PROFILE_LIST, skipping package cache"
fi

echo "Building ISO with mkarchiso..."
echo "Silent mode: $silent_mode"
## Think of this as a temp file for intermediate building
mkdir -p "$WORK_DIR"

ISO_LABEL="$NAME_$(date +%Y%m)"
# Limit to configured cores from VM settings using taskset (CPUs 0 through cores-1)
# Again named cores but its threads
if [ "$silent_mode" = "1" ]; then
    taskset -c 0-$((cores-1)) mkarchiso -v -w "$WORK_DIR" -o "$OUTPUT_DIR" -L "$ISO_LABEL" "$PROFILE_DIR" >/dev/null 2>&1
else
    taskset -c 0-$((cores-1)) mkarchiso -v -w "$WORK_DIR" -o "$OUTPUT_DIR" -L "$ISO_LABEL" "$PROFILE_DIR"
fi
# To use all available (this is VERY intese on CPU and can look frozen but always still succeeds)
chown -R $SUDO_USER:$SUDO_USER "$OUTPUT_DIR"

echo "Done! New ISO created in: $OUTPUT_DIR"
