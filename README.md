# namebench

A modern DNS benchmark tool — a spiritual successor to Google's abandoned [namebench](https://code.google.com/archive/p/namebench/) project.

Benchmarks public DNS resolvers by measuring query latency, reliability, and performance. Runs in a Docker container for portability.

## Resolvers Tested

Cloudflare, Google, Quad9, OpenDNS, NextDNS, AdGuard, Comodo, CleanBrowsing (configurable via `resolvers.txt`).

## Quick Start

```bash
# Build the image
docker build -t namebench .

# Run benchmark with defaults (16 resolvers, 50 queries each)
docker run --rm namebench

# Run with more queries and JSON output
docker run --rm namebench -q 100 -f json

# Save results to a local directory
docker run --rm -v "$(pwd)/results:/results" namebench -f csv

# List configured resolvers
docker run --rm namebench --list
```

## Run Without Docker

```bash
chmod +x benchmark.sh
./benchmark.sh
./benchmark.sh -q 100 -f json -o ./results
```

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `-r, --resolvers FILE` | Path to resolvers file | `/etc/namebench/resolvers.txt` |
| `-q, --queries NUM` | Queries per resolver | `50` |
| `-d, --domains FILE` | Custom domains file | built-in list of 20 domains |
| `-o, --output DIR` | Output directory | `/results` |
| `-f, --format FORMAT` | Output: `text`, `csv`, `json` | `text` |
| `-l, --list` | List resolvers and exit | |
| `-h, --help` | Show help | |

## Output Example

```
╔══════════════════════════════════════════════════════════════════════════════════╗
║                           DNS Benchmark Results                                 ║
╠══════════════════════════════════════════════════════════════════════════════════╣
║ Resolver           Name             Avg    Med    Min    Max    Rel%      Ok ║
╠══════════════════════════════════════════════════════════════════════════════════╣
║ 1.1.1.1            Cloudflare       4.2ms  3.0ms  2.0ms 18.0ms 100.0%  50/50 ║
║ 8.8.8.8            Google           8.1ms  7.0ms  5.0ms 22.0ms 100.0%  50/50 ║
║ 9.9.9.9            Quad9           12.3ms 11.0ms  8.0ms 35.0ms  98.0%  49/50 ║
╚══════════════════════════════════════════════════════════════════════════════════╝
```

## Custom Resolvers

Edit `resolvers.txt` or mount your own:

```bash
docker run --rm -v /path/to/my-resolvers.txt:/etc/namebench/resolvers.txt namebench
```

Format:
```
IP_ADDRESS    Name
8.8.8.8       Google-Primary
```
