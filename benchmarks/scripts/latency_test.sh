#!/bin/bash
# Latency test script

RESULTS_DIR="benchmarks/results"
mkdir -p $RESULTS_DIR

# Start a simple echo server on port 8080
echo "Starting echo server on port 8080..."
socat TCP-LISTEN:8080,reuseaddr,fork EXEC:'cat' &
SERVER_PID=$!

# Give the server a moment to start
sleep 1

# Test different forwarders
test_forwarder() {
    NAME=$1
    CMD=$2
    PORT=$3
    OUTPUT_FILE="$RESULTS_DIR/${NAME}_latency.txt"
    
    echo "Testing $NAME..."
    # Start the forwarder
    eval "$CMD" &
    FORWARDER_PID=$!
    
    # Give the forwarder a moment to start
    sleep 2
    
    # Run the test - 100 pings with 1kb payload
    echo "Measuring latency through $NAME..."
    python3 -c '
import socket
import time
import statistics
import sys

def measure_latency(host, port, num_tests=100, payload_size=1024):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect((host, port))
    
    latencies = []
    payload = b"x" * payload_size
    
    for i in range(num_tests):
        start_time = time.time()
        sock.sendall(payload)
        data = sock.recv(payload_size)
        end_time = time.time()
        
        if len(data) != payload_size:
            print(f"Error: Received {len(data)} bytes instead of {payload_size}")
            continue
            
        latency_ms = (end_time - start_time) * 1000
        latencies.append(latency_ms)
        sys.stdout.write(f"\rTest {i+1}/{num_tests}")
        sys.stdout.flush()
    
    sock.close()
    print("\nTests completed.")
    
    return {
        "min": min(latencies),
        "max": max(latencies),
        "mean": statistics.mean(latencies),
        "median": statistics.median(latencies),
        "p95": sorted(latencies)[int(len(latencies) * 0.95)],
        "p99": sorted(latencies)[int(len(latencies) * 0.99)]
    }

results = measure_latency("127.0.0.1", '$PORT')
print(f"\nLatency Results (ms):")
print(f"Min: {results['min']:.3f}")
print(f"Max: {results['max']:.3f}")
print(f"Mean: {results['mean']:.3f}")
print(f"Median: {results['median']:.3f}")
print(f"95th percentile: {results['p95']:.3f}")
print(f"99th percentile: {results['p99']:.3f}")
' > $OUTPUT_FILE
    
    # Kill the forwarder
    kill $FORWARDER_PID
    wait $FORWARDER_PID 2>/dev/null
    
    echo "$NAME test complete."
    sleep 2
}

# Test rport
test_forwarder "rport" "./target/release/rport --listen 127.0.0.1:9309 --target 127.0.0.1:8080" 9309

# Test socat
test_forwarder "socat" "socat TCP-LISTEN:9310,reuseaddr,fork TCP:127.0.0.1:8080" 9310

# Test nginx
create_nginx_conf() {
    cat > /tmp/nginx_bench.conf << 'NGINX_EOF'
worker_processes 1;
events {
    worker_connections 1024;
}
stream {
    server {
        listen 9311;
        proxy_pass 127.0.0.1:8080;
    }
}
NGINX_EOF
}
create_nginx_conf
test_forwarder "nginx" "nginx -c /tmp/nginx_bench.conf" 9311

# Clean up
kill $SERVER_PID
wait $SERVER_PID 2>/dev/null
echo "All tests completed. Results are in $RESULTS_DIR/"

# Parse results
echo "Parsing results..."
python3 -c '
import re
import glob
import os

results = {}
for file in glob.glob("benchmarks/results/*_latency.txt"):
    name = os.path.basename(file).split("_")[0]
    try:
        with open(file, "r") as f:
            content = f.read()
            match = re.search(r"Mean:\s+([\d.]+)", content)
            if match:
                mean = float(match.group(1))
                results[name] = mean
            else:
                results[name] = "parsing error"
    except:
        results[name] = "file error"

print("\nLatency Results (ms, lower is better):")
print("=" * 40)
for name, latency in sorted(results.items(), key=lambda x: 0 if isinstance(x[1], str) else x[1]):
    print(f"{name.ljust(15)}: {latency}")
'
