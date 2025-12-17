# EthoVision Tracking Platform for Place Preference Analysis

This is the provider interface that wraps [`/src/+io/+ethovision`](/src/+io/+ethovision/) to allow the processing of EthoVision tracking data.

The following features are supported, with notes on system setup where relevant:
- Scan, check, and filter for valid EthoVision projects; load and parse Media Files and Raw Data Excel files.
- Reliable support for X/Y position data for `center`, `nose`, and `tail` bodyparts (as provided in the base EthoVision software).
- Customizable handling of single arena setup
    - Arena name, Zone names, and Arena calibration measurements must be defined in configs.yml file (see [example config](/configs.full.yml)).
- Customizable handling of multi-arena setup (requires the Multiple-Arena-Module in EthoVision)
    - Arena names and configuration must be defined in configs.yml file (see [example config](/configs.full.yml)).
- `In zone` analysis must be set up in EthoVision prior to data export; zone names must match those defined in configs.yml file.