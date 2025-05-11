#!/bin/bash
# TCP throughput test script

RESULTS_DIR="benchmarks/results"
mkdir -p $RESULTS_DIR

# Start iperf3 server on port 8080
echo "Starting iperf3 server on port 8080..."
iperf3 -s -p 8080 &
SERVER_PID=$!

# Give the server a moment to start
sleep 1

# Test different forwarders
test_forwarder() {
    NAME=$1
    CMD=$2
    PORT=$3
    OUTPUT_FILE="$RESULTS_DIR/${NAME}_tcp_throughput.json"
    
    echo "Testing $NAME..."
    # Start the forwarder
    eval "$CMD" &
    FORWARDER_PID=$!
    
    # Give the forwarder a moment to start
    sleep 2
    
    # Run the test
    echo "Running iperf3 test through $NAME..."
    iperf3 -c 127.0.0.1 -p $PORT -J -t 30 > $OUTPUT_FILE
    
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

# Test nginx (requires a configured nginx.conf)
create_nginx_conf() {
    cat > /tmp/nginx_bench.conf << 'NGINX_EOF'
worker_processes 1;
events {
    worker_connections 1024;
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

# Test cloudflared (local connection)
test_forwarder "cloudflared" "cloudflared tunnel --url http://localhost:8080 --metrics localhost:9312" 9312

# Clean up
kill $SERVER_PID
wait $SERVER_PID 2>/dev/null
echo "All tests completed. Results are in $RESULTS_DIR/"

# Parse results
echo "Parsing results..."
python3 -c '
import json
import glob
import os

results = {}
for file in glob.glob("benchmarks/results/*_tcp_throughput.json"):
    name = os.path.basename(file).split("_")[0]
    try:
        data = json.load(open(file))
        bits_per_second = data["end"]["sum_received"]["bits_per_second"]
        mbps = bits_per_second / 1000000
        results[name] = mbps
    except:
        results[name] = "error"

print("\nTCP Throughput Results (Mbps):")
print("=" * 40)
for name, mbps in sorted(results.items(), key=lambda x: 0 if isinstance(x[1], str) else -x[1]):
    print(f"{name.ljust(15)}: {mbps}")
'
