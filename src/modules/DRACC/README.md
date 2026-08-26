# DRACC
This folder contains code for data export to DRACC

For typical in-house use, this module is often not necessary.

The DRACC `L1export` function requires a `TrackingProvider` named argument. The provider
must advertise the `L1export` capability; SLEAP currently supports this export, while
unsupported tracking providers are rejected.