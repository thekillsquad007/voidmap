# Data Sources

## Overview

Voidmap miners process real astronomical data from public archives. All data is freely available and requires no authentication.

---

## NASA MAST Archive

### What is MAST?

MAST (Mikulski Archive for Space Telescopes) is NASA's archive of astronomical data. It hosts data from TESS, Kepler, Hubble, and other missions.

### Data Available

- **TESS Light Curves**: 2-minute cadence photometry for 200,000+ stars
- **Kepler Light Curves**: 1-minute cadence for 150,000+ stars
- **Hubble Images**: Deep field imaging across multiple wavelengths

### How We Access It

```python
import lightkurve as lk

# Search for TESS data
search = lk.search_lightcurve("TIC 307210830", mission="TESS", author="SPOC")

# Download light curve
lc = search[0].download()

# Access data
time = lc.time.value          # Time in BTJD
flux = lc.pdcsap_flux.value   # Detrended flux
```

### API Endpoints

| Endpoint | URL |
|----------|-----|
| Portal | https://mast.stsci.edu |
| API | https://mast.stsci.edu/api/v0/invoke |
| File Download | https://mast.stsci.edu/api/v0.1/Download/file |

### Data Format

TESS light curves are FITS files containing:

| Column | Description |
|--------|-------------|
| TIME | Time (BTJD) |
| SAP_FLUX | Simple Aperture Photometry flux |
| PDCSAP_FLUX | Detrended flux (use this) |
| QUALITY | Quality flags |

---

## SDSS (Sloan Digital Sky Survey)

### What is SDSS?

SDSS is a major astronomical survey that has mapped over 1/3 of the sky. It provides images and spectra for millions of galaxies.

### Data Available

- **Galaxy Images**: RGB images of millions of galaxies
- **Spectra**: Optical spectra for classification
- **Catalogs**: Positions, magnitudes, classifications

### How We Access It

```python
import urllib.request

# Download galaxy cutout
url = ("https://skyserver.sdss.org/dr18/SkyServerWS/ImgCutout/getjpeg?"
       "ra=184.9511&dec=-0.8754&scale=0.4&width=64&height=64")

req = urllib.request.Request(url, headers={"User-Agent": "VoidmapMiner/1.0"})
with urllib.request.urlopen(req, timeout=30) as resp:
    img_data = resp.read()
```

### API Endpoints

| Endpoint | URL |
|----------|-----|
| SkyServer | https://skyserver.sdss.org/dr18 |
| Image Cutout | https://skyserver.sdss.org/dr18/SkyServerWS/ImgCutout/getjpeg |
| SQL Search | https://skyserver.sdss.org/dr18/SkyServerWS/SearchTools/SqlSearch |

### SQL Queries

```sql
-- Get spiral galaxies
SELECT TOP 100 p.objID, p.ra, p.dec, p.r, p.type
FROM PhotoPrimary p
WHERE p.type = 3 AND p.r < 20

-- Get galaxy images
SELECT s.specobjid, s.ra, s.dec, s.z
FROM SpecObj s
WHERE s.class = 'GALAXY' AND s.z < 0.1
```

---

## ZTF (Zwicky Transient Facility)

### What is ZTF?

ZTF is a robotic sky survey that scans the entire northern sky every 3 nights. It detects transient events like supernovae, asteroids, and variable stars.

### Data Available

- **Alerts**: Real-time notifications of transient events
- **Light Curves**: Photometry in g and r bands
- **Cutouts**: Science, template, and difference images

### How We Access It

```python
import urllib.request
import json

# Download alerts from Fink broker
url = "https://api.ztf.fink-portal.org/api/v1/latests"
payload = json.dumps({
    "class": "SN",
    "nalerts": 10,
    "output-format": "json"
}).encode()

req = urllib.request.Request(url, data=payload,
                             headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=30) as resp:
    alerts = json.loads(resp.read())
```

### API Endpoints

| Broker | URL |
|--------|-----|
| Fink | https://api.ztf.fink-portal.org |
| ALeRCE | https://ztf.alerce.online |
| Lasair | https://lasair-ztf.lsst.ac.uk/api |

### Alert Format

ZTF alerts contain:

| Field | Description |
|-------|-------------|
| objectId | Unique identifier |
| ra, dec | Sky coordinates |
| jd | Julian date |
| magpsf | Magnitude |
| fid | Filter (1=g, 2=r) |
| cutoutScience | Science image |
| cutoutTemplate | Template image |
| cutoutDifference | Difference image |

---

## Data Processing

### Exoplanet Transit Detection

1. **Download**: FITS file from MAST
2. **Quality filter**: Remove bad cadences (QUALITY > 0)
3. **Outlier removal**: 5-sigma clip
4. **Normalize**: Divide by median flux
5. **Fill NaNs**: Linear interpolation
6. **Phase-fold**: Fold at orbital period
7. **Resample**: Fixed-length arrays (201, 81)

### Galaxy Morphology

1. **Download**: JPEG from SDSS SkyServer
2. **Resize**: 224x224 pixels
3. **Normalize**: Float32 [0, 1]
4. **Classify**: Run ConvNeXT model

### Anomaly Detection

1. **Download**: Alerts from Fink broker
2. **Extract features**: Magnitude, time, position
3. **Encode**: Run through autoencoder
4. **Score**: Reconstruction error > 2σ = anomaly

---

## Data Quality

### Quality Metrics

| Metric | Description | Range |
|--------|-------------|-------|
| Quality Flags | Instrument-specific flags | 0 = good |
| Signal-to-Noise | Flux uncertainty | > 5 recommended |
| Cadence Coverage | Percentage of valid cadences | > 80% recommended |

### Known Issues

- **TESS**: Sector boundaries have gaps
- **SDSS**: Bright stars cause artifacts
- **ZTF**: Weather affects observations

---

## Contributing Data

If you have astronomical data to contribute:

1. Format it as FITS or JSON
2. Upload to IPFS
3. Submit to MiningPool contract
4. Miners will process it

---

## References

- [MAST Documentation](https://mast.stsci.edu/docs/)
- [SDSS Documentation](https://www.sdss.org/dr18/)
- [ZTF Documentation](https://ztf.uw.edu/)
- [lightkurve Documentation](https://docs.lightkurve.org/)
- [Astropy Documentation](https://docs.astropy.org/)
