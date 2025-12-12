# AIM - Arch ISO Modifier

ISO builder for creating custom Arch Linux installation media with pre-cached packages as a **priority source.**

> The advantage here is that if you build frequently, you can achieve 30-100MiB/s without using mirrors as much at the cost of the ISO being larger itself.

## Required Packages
> Assumes base-devel

```bash
sudo pacman -S archiso pacman-contrib
```

- **archiso** - Provides `mkarchiso` for building Arch ISOs
- **pacman-contrib** - Provides `pactree` for dependency resolution

## Configuration

Edit `general.conf`, `iso_profiles/something_profile.conf` and then `iso_mod.sh` 

## Usage

```bash
# Build ISO with default settings
sudo ./iso_mod.sh

# Output ISO will be in ./a/ directory
```

### Links

- https://www.gnu.org/software/xorriso/
- https://wiki.archlinux.org/title/Archiso