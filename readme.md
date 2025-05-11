# rport: High-Performance TCP Port Forwarder in Rust

`rport` is a lightweight, high-performance TCP port forwarding utility written in Rust. It efficiently forwards traffic between ports with minimal overhead, optionally supporting TLS encryption.

## Features

- **Fast and efficient** port forwarding with minimal latency
- **TLS support** for secure connections
- **Flexible configuration** for listen and target addresses
- **Concurrent connection handling** using Tokio async I/O
- **Minimal resource usage** with a small memory footprint

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/jeffasante/rport.git
cd rport

# Build with TLS support
cargo build --release --features tls

# Or build without TLS
cargo build --release
```

The compiled binary will be available at `./target/release/rport`.

## Usage

### Basic Usage

Forward local port 9309 to port 8080:

```bash
./rport --listen 127.0.0.1:9309 --target 127.0.0.1:8080
```

### With TLS

Enable TLS encryption:

```bash
./rport --listen 127.0.0.1:9309 --target 127.0.0.1:8080 --tls-cert cert.pem --tls-key key.pem
```

### Command-Line Options

```
Usage: rport --target <TARGET> --listen <LISTEN> [OPTIONS]

Options:
  --listen <LISTEN>    Local address to listen on (e.g., 0.0.0.0:9309) [default: 0.0.0.0:9309]
  --target <TARGET>    Remote address to forward to (e.g., example.com:80)
  --tls-cert <FILE>    Path to TLS certificate (optional)
  --tls-key <FILE>     Path to TLS private key (optional, requires --tls-cert)
  --help               Show this help message
```

## Examples

### Web Server Forwarding

Forward a local web server port:

```bash
# Start a web server on port 8080
python3 -m http.server 8080

# In another terminal, start rport
./rport --listen 127.0.0.1:9309 --target 127.0.0.1:8080

# Access the web server via the forwarded port
curl http://127.0.0.1:9309
```

### Secure Forwarding with TLS

```bash
# Generate self-signed certificates (for testing)
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes -subj '/CN=localhost'

# Start rport with TLS
./rport --listen 127.0.0.1:9309 --target 127.0.0.1:8080 --tls-cert cert.pem --tls-key key.pem

# Access via HTTPS
curl -k https://127.0.0.1:9309
```

### Generating TLS Certificates

For production use, you should use properly signed certificates. For testing or internal use, you can generate self-signed certificates:

#### Basic Self-Signed Certificate

```bash
# Generate a private key and a self-signed certificate
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes
```

You'll be prompted to enter certificate information. For testing, you can use defaults.

#### Certificate with Subject Alternative Names (SANs)

To create a certificate that works with both localhost and IP addresses:

```bash
# Create a config file
cat > cert.conf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = localhost

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
IP.1 = 127.0.0.1
IP.2 = 0.0.0.0
EOF

# Generate the certificate with SANs
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes -config cert.conf
```

#### Using the Certificates

Place the certificate (cert.pem) and key (key.pem) files in the same directory as rport or specify the full path:

```bash
./rport --listen 127.0.0.1:9309 --target 127.0.0.1:8080 --tls-cert /path/to/cert.pem --tls-key /path/to/key.pem
```

## Performance

rport has been benchmarked on an Apple M1 processor with the following results:

### HTTP Latency
| Metric | Value (ms) |
|--------|-----------|
| Minimum | 1.433 |
| Maximum | 4.473 |
| Average | 1.875 |
| Median | 1.743 |
| 95th Percentile | 3.353 |

### HTTP Throughput
| Concurrency | Requests/sec | Success Rate (%) |
|-------------|--------------|------------------|
| 1 | 613.29 | 100.00 |
| 5 | 1007.42 | 100.00 |
| 10 | 1040.74 | 100.00 |
| 20 | 579.66 | 100.00 |

### Memory Usage
| Metric | Value |
|--------|-------|
| RSS (Resident Set Size) | 2.93 MB |

These benchmarks demonstrate that rport is a high-performance TCP port forwarder with:
- Very low latency (median < 2ms)
- High throughput (>1000 req/sec with optimal concurrency)
- Minimal memory footprint (<3MB RAM usage)

For full benchmark details, see the [benchmark results](benchmarks/simple/results/).

## How It Works

rport uses [Tokio](https://tokio.rs/), an asynchronous runtime for Rust, to handle connections efficiently. When a client connects to the listen port, rport:

1. Accepts the incoming connection
2. Establishes a connection to the target
3. Efficiently copies data in both directions using async I/O
4. Optionally wraps the connection in TLS if configured

The implementation uses bidirectional copying with the `tokio::io::copy` function, ensuring maximum throughput with minimal CPU usage.

## Building from Source

### Prerequisites

- Rust 1.60 or higher
- For TLS support: OpenSSL development libraries

### Build Commands

```bash
# Clone the repository
git clone https://github.com/jeffasante/rport.git
cd rport

# Build with default features
cargo build --release

# Build with TLS support
cargo build --release --features tls

# Run tests
cargo test
```

## Troubleshooting

### TLS Certificate Issues

- **Certificate Not Found**: Ensure the paths to your cert.pem and key.pem files are correct
- **Permission Denied**: Make sure the files are readable by the user running rport
- **Handshake Failures**: Ensure the certificate is valid and not expired
- **Hostname Verification Errors**: When connecting to 127.0.0.1, ensure your certificate includes 127.0.0.1 in the Subject Alternative Name (SAN) field, or use the `-k` flag with curl to bypass verification

### Connection Problems

- **Address Already in Use**: Another program is already using the listen port
- **Connection Refused**: The target service is not running
- **Connection Reset**: The target service rejected the connection

## License

MIT License
