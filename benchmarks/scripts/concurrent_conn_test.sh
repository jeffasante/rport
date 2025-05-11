#!/bin/bash
# Concurrent connection handling test

RESULTS_DIR="benchmarks/results"
mkdir -p $RESULTS_DIR

# Start a simple HTTP server on port 8080
echo "Starting HTTP server on port 8080..."
cd /tmp && python3 -m http.server 8080 &
SERVER_PID=$!

# Give the server a moment to start
sleep 1

# Test different forwarders
test_forwarder() {
    NAME=$1
    CMD=$2
    PORT=$3
    OUTPUT_FILE="$RESULTS_DIR/${NAME}_concurrent_conn.txt"
    
    echo "Testing $NAME..."
    # Start the forwarder
    eval "$CMD" &
    FORWARDER_PID=$!
    
    # Give the forwarder a moment to start
    sleep 2
    
    # Run the test with varying concurrency levels
    echo "Testing concurrent connections through $NAME..." > $OUTPUT_FILE
    for CONCURRENCY in 10 50 100 200 500 1000; do
        echo "Testing with $CONCURRENCY concurrent connections..."
        echo "=== Concurrency: $CONCURRENCY ===" >> $OUTPUT_FILE
        
        python3 -c "
import asyncio
import aiohttp
import time
import sys

async def fetch(session, url):
    try:
        async with session.get(url) as response:
            return await response.text()
    except Exception as e:
        return str(e)

async def main():
    concurrency = $CONCURRENCY
    url = 'http://127.0.0.1:$PORT/'
    
    start_time = time.time()
    
    async with aiohttp.ClientSession() as session:
        tasks = []
        for i in range(concurrency):
            tasks.append(fetch(session, url))
        
        results = await asyncio.gather(*tasks)
        
        success = sum(1 for r in results if not r.startswith('Exception'))
        failure = concurrency - success
        
        end_time = time.time()
        elapsed = end_time - start_time
        
        print(f'Completed {concurrency} requests in {elapsed:.2f} seconds')
        print(f'Success: {success}, Failure: {failure}')
        print(f'Success rate: {(success/concurrency)*100:.2f}%')

asyncio.run(main())
" >> $OUTPUT_FILE 2>&1
        
        sleep 1
    done
    
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
worker_processes auto;
events {
    worker_connections 4096;
}
http {
    server {
        listen 9311;
        location / {
            proxy_pass http://127.0.0.1:8080\;
        }
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

# Parse and summarize results
echo "Parsing results..."
python3 -c '
import re
import glob
import os

def parse_file(filename):
    results = {}
    with open(filename, "r") as f:
        content = f.read()
        sections = content.split("=== Concurrency:")
        
        for section in sections[1:]:  # Skip the first element which is before the first marker
            match_concurrency = re.search(r"(\d+) ===", section)
            match_success_rate = re.search(r"Success rate: ([\d.]+)%", section)
            
            if match_concurrency and match_success_rate:
                concurrency = int(match_concurrency.group(1))
                success_rate = float(match_success_rate.group(1))
                results[concurrency] = success_rate
    
    return results

all_results = {}
for file in glob.glob("benchmarks/results/*_concurrent_conn.txt"):
    name = os.path.basename(file).split("_")[0]
    try:
        file_results = parse_file(file)
        all_results[name] = file_results
    except Exception as e:
        print(f"Error parsing {file}: {e}")
        all_results[name] = {}

# Print a table with results
print("\nConcurrent Connection Test Results (Success Rate %):")
print("=" * 60)

# Get unique concurrency levels
all_concurrency = set()
for forwarder in all_results.values():
    all_concurrency.update(forwarder.keys())
all_concurrency = sorted(all_concurrency)

# Print header
header = "Forwarder".ljust(15)
for c in all_concurrency:
    header += f" | {c:>5}"
print(header)
print("-" * 60)

# Print results for each forwarder
for name, results in sorted(all_results.items()):
    line = name.ljust(15)
    for c in all_concurrency:
        if c in results:
            line += f" | {results[c]:>5.1f}"
        else:
            line += f" | {'-':>5}"
    print(line)
'
