#!/bin/bash
# Memory usage test script

RESULTS_DIR="benchmarks/results"
mkdir -p $RESULTS_DIR

# Function to measure memory usage
measure_memory() {
    NAME=$1
    CMD=$2
    DURATION=$3  # in seconds
    OUTPUT_FILE="$RESULTS_DIR/${NAME}_memory_usage.txt"
    
    echo "Measuring memory usage for $NAME for $DURATION seconds..."
    
    # Start the process
    eval "$CMD" &
    PID=$!
    
    # Give it a moment to initialize
    sleep 2
    
    # Sample memory usage periodically
    echo "Time(s),RSS(KB),VSZ(KB)" > $OUTPUT_FILE
    for i in $(seq 1 $DURATION); do
        if ps -p $PID > /dev/null; then
            # Get memory usage (RSS and VSZ) in KB
            MEM_INFO=$(ps -o rss,vsz -p $PID | tail -1)
            RSS=$(echo $MEM_INFO | awk '{print $1}')
            VSZ=$(echo $MEM_INFO | awk '{print $2}')
            echo "$i,$RSS,$VSZ" >> $OUTPUT_FILE
        else
            echo "Process terminated unexpectedly!"
            break
        fi
        sleep 1
    done
    
    # Kill the process
    kill $PID 2>/dev/null
    wait $PID 2>/dev/null
    
    echo "Memory measurement for $NAME complete."
    sleep 1
}

# Measure memory for different forwarders (run for 30 seconds each)
measure_memory "rport" "./target/release/rport --listen 127.0.0.1:9309 --target 127.0.0.1:8080" 30
measure_memory "socat" "socat TCP-LISTEN:9310,reuseaddr,fork TCP:127.0.0.1:8080" 30
measure_memory "nginx" "nginx -c /tmp/nginx_bench.conf" 30

echo "All measurements completed. Results are in $RESULTS_DIR/"

# Parse and visualize results
echo "Generating summary..."
python3 -c '
import pandas as pd
import glob
import os

summary = {"Forwarder": [], "Peak RSS (MB)": [], "Average RSS (MB)": [], "Peak VSZ (MB)": [], "Average VSZ (MB)": []}

for file in glob.glob("benchmarks/results/*_memory_usage.txt"):
    name = os.path.basename(file).split("_")[0]
    
    try:
        df = pd.read_csv(file)
        peak_rss = df["RSS(KB)"].max() / 1024  # Convert to MB
        avg_rss = df["RSS(KB)"].mean() / 1024
        peak_vsz = df["VSZ(KB)"].max() / 1024
        avg_vsz = df["VSZ(KB)"].mean() / 1024
        
        summary["Forwarder"].append(name)
        summary["Peak RSS (MB)"].append(peak_rss)
        summary["Average RSS (MB)"].append(avg_rss)
        summary["Peak VSZ (MB)"].append(peak_vsz)
        summary["Average VSZ (MB)"].append(avg_vsz)
    except Exception as e:
        print(f"Error processing {file}: {e}")

print("\nMemory Usage Summary:")
print("=" * 80)
print(f"{'Forwarder':<15} | {'Peak RSS (MB)':<15} | {'Avg RSS (MB)':<15} | {'Peak VSZ (MB)':<15} | {'Avg VSZ (MB)':<15}")
print("-" * 80)

for i in range(len(summary["Forwarder"])):
    print(f"{summary['Forwarder'][i]:<15} | {summary['Peak RSS (MB)'][i]:>15.2f} | {summary['Average RSS (MB)'][i]:>15.2f} | {summary['Peak VSZ (MB)'][i]:>15.2f} | {summary['Average VSZ (MB)'][i]:>15.2f}")
'
