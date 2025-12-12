# AIM - Arch ISO Modifier

ISO builder for creating custom Arch Linux installation media with pre-cached packages as a **priority source.**

## Required Packages
> Assumes base-devel

```bash
sudo pacman -S archiso pacman-contrib
```

- **archiso** - Provides `mkarchiso` for building Arch ISOs
- **pacman-contrib** - Provides `pactree` for dependency resolution

## Configuration

Edit `geneneral.conf` and the `iso_mod.sh` to customize your ISO:

## Usage

```bash
# Build ISO with default settings
sudo ./iso_mod.sh

# Output ISO will be in ./a/ directory
```