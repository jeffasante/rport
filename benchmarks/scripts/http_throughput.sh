#!/bin/bash
# HTTP request throughput test script

RESULTS_DIR="benchmarks/results"
mkdir -p $RESULTS_DIR

# Create a simple test server file
mkdir -p /tmp/http_test
cat > /tmp/http_test/index.html << 'HTML_EOF'
<!DOCTYPE html>
<html>
<head>
    <title>rport Benchmark Test</title>
</head>
<body>
    <h1>rport Benchmark Test Page</h1>
    <p>This is a test page for benchmarking port forwarding performance.</p>
    <div style="height: 800px; background: linear-gradient(to right, red, orange, yellow, green, blue, indigo, violet);">
        Some content to make the page a bit larger
    </div>
</body>
</html>
HTML_EOF

# Start Python HTTP server on port 8080
echo "Starting HTTP server on port 8080..."
cd /tmp/http_test && python3 -m http.server 8080 &
SERVER_PID=$!

# Give the server a moment to start
sleep 1

# Test different forwarders
test_forwarder() {
    NAME=$1
    CMD=$2
    PORT=$3
    OUTPUT_FILE="$RESULTS_DIR/${NAME}_http_throughput.json"
    
    echo "Testing $NAME..."
    # Start the forwarder
    eval "$CMD" &
    FORWARDER_PID=$!
    
    # Give the forwarder a moment to start
    sleep 2
    
    # Run the test with drill (HTTP benchmark tool)
    echo "Running HTTP benchmark through $NAME..."
    cat > /tmp/drill_${NAME}.toml << DRILL_EOF
base = "http://127.0.0.1:$PORT"
concurrency = 50
iterations = 10000
rampup = 2

[[request]]
url = "/"
DRILL_EOF

    drill --benchmark /tmp/drill_${NAME}.toml > $OUTPUT_FILE
    
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
import re
import glob
import os

results = {}
for file in glob.glob("benchmarks/results/*_http_throughput.json"):
    name = os.path.basename(file).split("_")[0]
    try:
        with open(file, "r") as f:
            content = f.read()
            # Extract requests per second
            match = re.search(r"Requests per second:\s+([\d.]+)", content)
            if match:
                rps = float(match.group(1))
                results[name] = rps
            else:
                results[name] = "parsing error"
    except:
        results[name] = "file error"

print("\nHTTP Throughput Results (Requests/sec):")
print("=" * 40)
for name, rps in sorted(results.items(), key=lambda x: 0 if isinstance(x[1], str) else -x[1]):
    print(f"{name.ljust(15)}: {rps}")
'
