# Proof of Useful Work (PoUW)

## What is Proof of Useful Work?

Traditional Proof of Work (Bitcoin, Ethereum pre-merge) wastes energy on hash puzzles. Miners compute SHA-256 hashes billions of times, producing nothing useful.

**Proof of Useful Work** directs that computation toward real scientific problems. Instead of finding hash collisions, miners process real astronomical data with real ML models.

---

## Voidmap's PoUW Model

### The Pipeline

```
NASA Archive → FITS Download → Preprocessing → ML Inference → Quality Score → VOID Reward
```

1. **Download real data** from public archives (MAST, SDSS, ZTF)
2. **Preprocess** (filter, normalize, phase-fold)
3. **Run ML model** on GPU (TransitCNN, Zoobot, AnomalyAE)
4. **Compute quality score** from model metrics
5. **Submit results** to MiningPool contract
6. **Receive VOID** based on quality

---

## Mining Tasks

### 1. Exoplanet Transit Detection

**Data**: TESS 2-minute cadence light curves from MAST
**Model**: AstroNetCNN (244K params, 89% accuracy)
**Output**: Planet / False Positive / No Signal classification

**What it does**:
- Downloads FITS files from NASA MAST archive
- Extracts PDCSAP flux (detrended light curve)
- Quality filters bad cadences
- Outlier removal (5-sigma clip)
- Normalize and fill NaNs
- Phase-fold at orbital period
- Resample to fixed-length arrays (201 global, 81 local)
- Run multi-branch 1D CNN
- Output classification with confidence

**Quality scoring**:
- Based on model confidence (softmax probability)
- Higher confidence = higher quality
- Range: 50-100

### 2. Galaxy Morphology Classification

**Data**: SDSS DR18 galaxy images
**Model**: GalaxyClassifier (ConvNeXT architecture)
**Output**: Spiral / Elliptical / Irregular / Merger / Unknown

**What it does**:
- Downloads galaxy cutouts from SDSS SkyServer
- Resize to 224x224 RGB
- Normalize to [0, 1]
- Run ConvNeXT classifier
- Output morphology class with probabilities

**Quality scoring**:
- Based on classification confidence
- Higher confidence = higher quality
- Range: 50-100

### 3. Anomaly Detection

**Data**: ZTF alerts from Fink broker
**Model**: AnomalyAE (autoencoder)
**Output**: Anomaly scores + flags

**What it does**:
- Downloads alerts from ZTF/Fink API
- Extract features from alert stream
- Run autoencoder
- Compute reconstruction error
- Flag anomalies (> 2σ from mean)

**Quality scoring**:
- Based on anomaly score magnitude
- More anomalous = higher quality
- Range: 50-100

---

## Quality Thresholds

| Score | Status | Reward | Description |
|-------|--------|--------|-------------|
| < 50 | REJECTED | 0 | Noise, invalid work |
| 50-69 | ACCEPTED | 1x | Base reward |
| 70-89 | GOOD | 1.2x | Bonus for high quality |
| 90-100 | EXCELLENT | 1.5x | Maximum reward |

---

## What Makes This "Useful"?

### Real Data, Real Science

- **TESS light curves**: Used by NASA to discover exoplanets
- **SDSS images**: Used by astronomers to study galaxy evolution
- **ZTF alerts**: Used to detect supernovae and other transients

### Verified Results

- Results stored on IPFS with CID on-chain
- Anyone can verify predictions
- Models are pre-trained and reproducible

### Scientific Value

- Exoplanet candidates can be submitted to NASA
- Galaxy classifications contribute to Galaxy Zoo
- Anomaly detections help find rare transients

---

## Why Not Just Use Centralized Computing?

1. **Scale**: 1000s of GPUs > 1 data center
2. **Cost**: Miners pay for their own electricity
3. **Decentralization**: No single point of failure
4. **Incentive alignment**: Miners earn for useful work
5. **Open data**: Results publicly accessible

---

## Comparison to Traditional PoW

| Aspect | Bitcoin PoW | Voidmap PoUW |
|--------|-------------|--------------|
| Computation | SHA-256 hashing | ML inference |
| Output | Hash collisions | Scientific predictions |
| Usefulness | None | Exoplanet detection |
| Energy waste | High | Low (useful work) |
| Hardware | ASICs only | GPUs only |
| Centralization risk | High (ASIC farms) | Low (consumer GPUs) |

---

## Quality Verification

### On-Chain

- `inputHash`: Hash of input data (verifiable against archive)
- `outputHash`: Hash of output predictions
- `modelHash`: Hash of model weights
- `ipfsCID`: IPFS CID of full results

### Off-Chain

- Results saved locally at `~/.voidmap/results/`
- Full predictions accessible via IPFS gateway
- Models are pre-trained and publicly available

---

## Future Improvements

1. **More tasks**: Additional ML tasks (spectral classification, etc.)
2. **Better models**: Larger, more accurate pre-trained models
3. **Real-time streaming**: Process ZTF alerts in real-time
4. **Result distribution**: Submit results to NASA/ESA archives
5. **Community models**: Allow miners to contribute custom models
