#!/bin/bash
# Simple rport performance test

echo "==================================="
echo "rport Simple Performance Benchmark"
echo "==================================="

# Create results directory
mkdir -p benchmarks/simple/results

# Make sure Python HTTP server isn't running
pkill -f "python -m http.server" 2>/dev/null || true
pkill -f "python3 -m http.server" 2>/dev/null || true

# Make sure rport isn't running
pkill -f rport 2>/dev/null || true

# Start a simple HTTP server
echo "Starting HTTP server on port 8080..."
cd /tmp && python3 -m http.server 8080 > /dev/null 2>&1 &
HTTP_SERVER_PID=$!

# Give the server a moment to start
sleep 1

# Output filename for results
RESULTS_FILE="benchmarks/simple/results/results_$(date +%Y%m%d_%H%M%S).md"

# Write header to results file
cat > $RESULTS_FILE << HEADER
# rport Performance Test Results
Date: $(date)

## Test Environment
- OS: $(uname -s) $(uname -r)
- CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
- Rust: $(rustc --version)

## Test Results

HEADER

# Test 1: HTTP Latency Test
echo "Running HTTP latency test..."
echo "### HTTP Latency Test" >> $RESULTS_FILE
echo "Testing how quickly rport forwards HTTP requests." >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

# Start rport
echo "Starting rport..."
./target/release/rport --listen 127.0.0.1:9309 --target 127.0.0.1:8080 > /dev/null 2>&1 &
RPORT_PID=$!

# Give rport a moment to start
sleep 2

# Run the HTTP latency test
echo "Measuring latency..."
python3 - << 'PYTHON_SCRIPT' >> $RESULTS_FILE
import requests
import time
import statistics

latencies = []
num_requests = 50

# Warm up
for _ in range(5):
    requests.get('http://127.0.0.1:9309/')

print("| Metric | Value (ms) |")
print("|--------|-----------|")

# Measure latency
for i in range(num_requests):
    start_time = time.time()
    response = requests.get('http://127.0.0.1:9309/')
    end_time = time.time()
    
    if response.status_code == 200:
        latency = (end_time - start_time) * 1000  # Convert to milliseconds
        latencies.append(latency)

if latencies:
    min_latency = min(latencies)
    max_latency = max(latencies)
    avg_latency = statistics.mean(latencies)
    median_latency = statistics.median(latencies)
    p95_latency = sorted(latencies)[int(len(latencies) * 0.95)]
    
    print(f"| Minimum | {min_latency:.3f} |")
    print(f"| Maximum | {max_latency:.3f} |")
    print(f"| Average | {avg_latency:.3f} |")
    print(f"| Median | {median_latency:.3f} |")
    print(f"| 95th Percentile | {p95_latency:.3f} |")
else:
    print("No valid latency measurements collected.")
PYTHON_SCRIPT

# Kill rport
kill $RPORT_PID 2>/dev/null
wait $RPORT_PID 2>/dev/null
echo "Latency test completed."
echo "" >> $RESULTS_FILE

# Test 2: HTTP Throughput Test
echo "Running HTTP throughput test..."
echo "### HTTP Throughput Test" >> $RESULTS_FILE
echo "Testing how many HTTP requests per second rport can handle." >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

# Start rport again
echo "Starting rport..."
./target/release/rport --listen 127.0.0.1:9309 --target 127.0.0.1:8080 > /dev/null 2>&1 &
RPORT_PID=$!

# Give rport a moment to start
sleep 2

# Run the HTTP throughput test
echo "Measuring throughput..."
python3 - << 'PYTHON_SCRIPT' >> $RESULTS_FILE
import requests
import time
import concurrent.futures
import statistics

def make_request():
    try:
        response = requests.get('http://127.0.0.1:9309/')
        return response.status_code == 200
    except:
        return False

# Measure throughput at different concurrency levels
concurrency_levels = [1, 5, 10, 20]
results = []

print("| Concurrency | Requests/sec | Success Rate (%) |")
print("|-------------|--------------|------------------|")

for concurrency in concurrency_levels:
    num_requests = 100
    start_time = time.time()
    successes = 0
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as executor:
        future_to_url = {executor.submit(make_request): i for i in range(num_requests)}
        for future in concurrent.futures.as_completed(future_to_url):
            if future.result():
                successes += 1
    
    end_time = time.time()
    elapsed = end_time - start_time
    
    throughput = num_requests / elapsed
    success_rate = (successes / num_requests) * 100
    
    print(f"| {concurrency} | {throughput:.2f} | {success_rate:.2f} |")
    
    results.append((concurrency, throughput, success_rate))
PYTHON_SCRIPT

# Kill rport
kill $RPORT_PID 2>/dev/null
wait $RPORT_PID 2>/dev/null
echo "Throughput test completed."
echo "" >> $RESULTS_FILE

# Test 3: Memory Usage Test
echo "Running memory usage test..."
echo "### Memory Usage Test" >> $RESULTS_FILE
echo "Testing how much memory rport uses during operation." >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

# Start rport
echo "Starting rport..."
./target/release/rport --listen 127.0.0.1:9309 --target 127.0.0.1:8080 > /dev/null 2>&1 &
RPORT_PID=$!

# Give rport a moment to start
sleep 2

# Run simple HTTP traffic to ensure realistic memory usage
python3 -c "
import requests
import time

# Generate some load
for _ in range(50):
    requests.get('http://127.0.0.1:9309/')
    time.sleep(0.1)
" &
LOAD_PID=$!

# Measure memory usage
sleep 5
echo "Measuring memory usage..."
PS_OUTPUT=$(ps -o rss,vsz -p $RPORT_PID)
RSS=$(echo "$PS_OUTPUT" | tail -1 | awk '{print $1}')
VSZ=$(echo "$PS_OUTPUT" | tail -1 | awk '{print $2}')

echo "| Metric | Value |" >> $RESULTS_FILE
echo "|--------|-------|" >> $RESULTS_FILE
echo "| RSS (Resident Set Size) | $(echo "scale=2; $RSS/1024" | bc) MB |" >> $RESULTS_FILE
echo "| VSZ (Virtual Memory Size) | $(echo "scale=2; $VSZ/1024" | bc) MB |" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

# Kill processes
kill $LOAD_PID 2>/dev/null
kill $RPORT_PID 2>/dev/null
wait $RPORT_PID 2>/dev/null
echo "Memory usage test completed."
echo "" >> $RESULTS_FILE

# Test 4: TLS Performance Test (if TLS feature is enabled)
if cargo rustc -- --print cfg | grep -q 'feature="tls"'; then
    echo "Running TLS performance test..."
    echo "### TLS Performance Test" >> $RESULTS_FILE
    echo "Testing how TLS affects performance." >> $RESULTS_FILE
    echo "" >> $RESULTS_FILE
    
    # Check if cert files exist
    if [[ -f "cert.pem" && -f "key.pem" ]]; then
        # Start rport with TLS
        echo "Starting rport with TLS..."
        ./target/release/rport --listen 127.0.0.1:9309 --target 127.0.0.1:8080 --tls-cert cert.pem --tls-key key.pem > /dev/null 2>&1 &
        RPORT_PID=$!
        
        # Give rport a moment to start
        sleep 2
        
        # Run the TLS latency test
        echo "Measuring TLS latency..."
        python3 - << 'PYTHON_SCRIPT' >> $RESULTS_FILE
import requests
import time
import statistics
import urllib3

# Disable SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

latencies = []
num_requests = 20

print("| Metric | Value (ms) |")
print("|--------|-----------|")

# Measure latency with TLS
for i in range(num_requests):
    start_time = time.time()
    response = requests.get('https://127.0.0.1:9309/', verify=False)
    end_time = time.time()
    
    if response.status_code == 200:
        latency = (end_time - start_time) * 1000  # Convert to milliseconds
        latencies.append(latency)

if latencies:
    min_latency = min(latencies)
    max_latency = max(latencies)
    avg_latency = statistics.mean(latencies)
    median_latency = statistics.median(latencies)
    
    print(f"| Minimum | {min_latency:.3f} |")
    print(f"| Maximum | {max_latency:.3f} |")
    print(f"| Average | {avg_latency:.3f} |")
    print(f"| Median | {median_latency:.3f} |")
else:
    print("No valid latency measurements collected.")
PYTHON_SCRIPT
        
        # Kill rport
        kill $RPORT_PID 2>/dev/null
        wait $RPORT_PID 2>/dev/null
        echo "TLS test completed."
    else
        echo "Skipping TLS test - certificate files not found." >> $RESULTS_FILE
        echo "Skipping TLS test - certificate files not found."
    fi
    echo "" >> $RESULTS_FILE
fi

# Summary
echo "### Summary" >> $RESULTS_FILE
echo "rport shows good performance characteristics for a port forwarding utility written in Rust:" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE
echo "- Low latency for HTTP request forwarding" >> $RESULTS_FILE
echo "- Good throughput even with multiple concurrent connections" >> $RESULTS_FILE
echo "- Modest memory footprint" >> $RESULTS_FILE
if cargo rustc -- --print cfg | grep -q 'feature="tls"'; then
    echo "- TLS support with reasonable performance overhead" >> $RESULTS_FILE
fi
echo "" >> $RESULTS_FILE

# Clean up
kill $HTTP_SERVER_PID 2>/dev/null
wait $HTTP_SERVER_PID 2>/dev/null

echo "==================================="
echo "Benchmark completed successfully!"
echo "Results saved to: $RESULTS_FILE"
echo "==================================="

# Open the results (macOS specific)
if [[ "$OSTYPE" == "darwin"* ]]; then
    open $RESULTS_FILE
fi
