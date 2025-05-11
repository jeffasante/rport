#!/bin/bash
# Master benchmark script

echo "===================================="
echo "rport Performance Benchmarking Suite"
echo "===================================="

# Make sure we're in the project root
cd "$(dirname "$0")/.."

# Ensure build is up to date
echo "Building release version of rport..."
cargo build --release --features tls

# Run all benchmarks
echo -e "\nRunning TCP throughput test..."
./benchmarks/scripts/tcp_throughput.sh

echo -e "\nRunning HTTP throughput test..."
./benchmarks/scripts/http_throughput.sh

echo -e "\nRunning latency test..."
./benchmarks/scripts/latency_test.sh

echo -e "\nRunning concurrent connection test..."
./benchmarks/scripts/concurrent_conn_test.sh

echo -e "\nRunning memory usage test..."
./benchmarks/scripts/memory_usage.sh

echo -e "\nGenerating comprehensive report..."
python3 -c '
import glob
import os
import re
import json
import pandas as pd
import matplotlib.pyplot as plt
from datetime import datetime

# Create results directory if it doesnt exist
os.makedirs("benchmarks/results/reports", exist_ok=True)

report_file = f"benchmarks/results/reports/benchmark_report_{datetime.now().strftime(\"%Y%m%d_%H%M%S\")}.md"

with open(report_file, "w") as f:
    f.write("# rport Performance Benchmark Report\n\n")
    f.write(f"Date: {datetime.now().strftime(\"%Y-%m-%d %H:%M:%S\")}\n\n")
    
    # System information
    f.write("## System Information\n\n")
    try:
        import platform
        import psutil
        
        f.write(f"- OS: {platform.system()} {platform.release()}\n")
        f.write(f"- CPU: {platform.processor()} ({psutil.cpu_count()} cores)\n")
        f.write(f"- Memory: {psutil.virtual_memory().total / (1024**3):.2f} GB\n")
        f.write(f"- Python: {platform.python_version()}\n")
        f.write(f"- Rust: {os.popen(\"rustc --version\").read().strip()}\n\n")
    except:
        f.write("System information not available\n\n")
    
    # TCP Throughput
    f.write("## TCP Throughput\n\n")
    f.write("| Forwarder | Throughput (Mbps) |\n")
    f.write("|-----------|------------------|\n")
    
    tcp_results = {}
    for file in glob.glob("benchmarks/results/*_tcp_throughput.json"):
        name = os.path.basename(file).split("_")[0]
        try:
            data = json.load(open(file))
            bits_per_second = data["end"]["sum_received"]["bits_per_second"]
            mbps = bits_per_second / 1000000
            tcp_results[name] = mbps
            f.write(f"| {name} | {mbps:.2f} |\n")
        except:
            f.write(f"| {name} | Error |\n")
    
    f.write("\n")
    
    # HTTP Throughput
    f.write("## HTTP Throughput\n\n")
    f.write("| Forwarder | Requests/second |\n")
    f.write("|-----------|----------------|\n")
    
    http_results = {}
    for file in glob.glob("benchmarks/results/*_http_throughput.json"):
        name = os.path.basename(file).split("_")[0]
        try:
            with open(file, "r") as file_handle:
                content = file_handle.read()
                match = re.search(r"Requests per second:\s+([\d.]+)", content)
                if match:
                    rps = float(match.group(1))
                    http_results[name] = rps
                    f.write(f"| {name} | {rps:.2f} |\n")
                else:
                    f.write(f"| {name} | Parsing error |\n")
        except:
            f.write(f"| {name} | File error |\n")
    
    f.write("\n")
    
    # Latency
    f.write("## Latency\n\n")
    f.write("| Forwarder | Mean (ms) | Median (ms) | 95th Percentile (ms) |\n")
    f.write("|-----------|-----------|-------------|-----------------------|\n")
    
    latency_results = {}
    for file in glob.glob("benchmarks/results/*_latency.txt"):
        name = os.path.basename(file).split("_")[0]
        try:
            with open(file, "r") as file_handle:
                content = file_handle.read()
                mean_match = re.search(r"Mean:\s+([\d.]+)", content)
                median_match = re.search(r"Median:\s+([\d.]+)", content)
                p95_match = re.search(r"95th percentile:\s+([\d.]+)", content)
                
                if mean_match and median_match and p95_match:
                    mean = float(mean_match.group(1))
                    median = float(median_match.group(1))
                    p95 = float(p95_match.group(1))
                    
                    latency_results[name] = mean
                    f.write(f"| {name} | {mean:.3f} | {median:.3f} | {p95:.3f} |\n")
                else:
                    f.write(f"| {name} | Parsing error | - | - |\n")
        except:
            f.write(f"| {name} | File error | - | - |\n")
    
    f.write("\n")
    
    # Memory Usage
    f.write("## Memory Usage\n\n")
    f.write("| Forwarder | Peak RSS (MB) | Average RSS (MB) |\n")
    f.write("|-----------|---------------|------------------|\n")
    
    memory_results = {}
    for file in glob.glob("benchmarks/results/*_memory_usage.txt"):
        name = os.path.basename(file).split("_")[0]
        try:
            df = pd.read_csv(file)
            peak_rss = df["RSS(KB)"].max() / 1024  # Convert to MB
            avg_rss = df["RSS(KB)"].mean() / 1024
            
            memory_results[name] = peak_rss
            f.write(f"| {name} | {peak_rss:.2f} | {avg_rss:.2f} |\n")
        except:
            f.write(f"| {name} | Error | Error |\n")
    
    f.write("\n")
    
    # Concurrent Connection Test
    f.write("## Concurrent Connection Handling\n\n")
    f.write("Success Rate (%) by Concurrency Level:\n\n")
    f.write("| Forwarder | 10 | 50 | 100 | 200 | 500 | 1000 |\n")
    f.write("|-----------|----|----|-----|-----|-----|------|\n")
    
    for file in glob.glob("benchmarks/results/*_concurrent_conn.txt"):
        name = os.path.basename(file).split("_")[0]
        try:
            with open(file, "r") as file_handle:
                content = file_handle.read()
                results = {}
                
                for concurrency in [10, 50, 100, 200, 500, 1000]:
                    pattern = f"=== Concurrency: {concurrency} ===.*?Success rate: ([\d.]+)%"
                    match = re.search(pattern, content, re.DOTALL)
                    if match:
                        results[concurrency] = float(match.group(1))
                    else:
                        results[concurrency] = None
                
                line = f"| {name} |"
                for concurrency in [10, 50, 100, 200, 500, 1000]:
                    if results[concurrency] is not None:
                        line += f" {results[concurrency]:.1f} |"
                    else:
                        line += " - |"
                
                f.write(line + "\n")
        except:
            f.write(f"| {name} | Error | Error | Error | Error | Error | Error |\n")
    
    f.write("\n")
    
    # Summary
    f.write("## Performance Summary\n\n")
    
    # Collect all forwarder names
    forwarders = set()
    for results in [tcp_results, http_results, latency_results, memory_results]:
        forwarders.update(results.keys())
    
    f.write("| Metric | Best Performer | Notes |\n")
    f.write("|--------|---------------|---------|\n")
    
    # TCP Throughput
    if tcp_results:
        best = max(tcp_results.items(), key=lambda x: x[1])
        f.write(f"| TCP Throughput | {best[0]} ({best[1]:.2f} Mbps) | Higher is better |\n")
    
    # HTTP Throughput
    if http_results:
        best = max(http_results.items(), key=lambda x: x[1])
        f.write(f"| HTTP Throughput | {best[0]} ({best[1]:.2f} req/s) | Higher is better |\n")
    
    # Latency
    if latency_results:
        best = min(latency_results.items(), key=lambda x: x[1])
        f.write(f"| Latency | {best[0]} ({best[1]:.3f} ms) | Lower is better |\n")
    
    # Memory Usage
    if memory_results:
        best = min(memory_results.items(), key=lambda x: x[1])
        f.write(f"| Memory Usage | {best[0]} ({best[1]:.2f} MB) | Lower is better |\n")
    
    f.write("\n")
    f.write("## Conclusion\n\n")
    f.write("This benchmark compares rport against other popular port forwarding solutions. ")
    
    # Try to determine where rport shines
    strengths = []
    
    if tcp_results and "rport" in tcp_results:
        rport_tcp = tcp_results["rport"]
        avg_tcp = sum([v for k, v in tcp_results.items() if k != "rport"]) / (len(tcp_results) - 1) if len(tcp_results) > 1 else 0
        if rport_tcp > avg_tcp:
            strengths.append(f"higher TCP throughput ({rport_tcp:.2f} Mbps vs. avg {avg_tcp:.2f} Mbps)")
    
    if http_results and "rport" in http_results:
        rport_http = http_results["rport"]
        avg_http = sum([v for k, v in http_results.items() if k != "rport"]) / (len(http_results) - 1) if len(http_results) > 1 else 0
        if rport_http > avg_http:
            strengths.append(f"higher HTTP request throughput ({rport_http:.2f} req/s vs. avg {avg_http:.2f} req/s)")
    
    if latency_results and "rport" in latency_results:
        rport_latency = latency_results["rport"]
        avg_latency = sum([v for k, v in latency_results.items() if k != "rport"]) / (len(latency_results) - 1) if len(latency_results) > 1 else 0
        if rport_latency < avg_latency:
            strengths.append(f"lower latency ({rport_latency:.3f} ms vs. avg {avg_latency:.3f} ms)")
    
    if memory_results and "rport" in memory_results:
        rport_memory = memory_results["rport"]
        avg_memory = sum([v for k, v in memory_results.items() if k != "rport"]) / (len(memory_results) - 1) if len(memory_results) > 1 else 0
        if rport_memory < avg_memory:
            strengths.append(f"lower memory usage ({rport_memory:.2f} MB vs. avg {avg_memory:.2f} MB)")
    
    if strengths:
        f.write("rport shows strengths in: " + ", ".join(strengths) + ". ")
    
    f.write("\n\nFor detailed analysis, refer to the individual sections above.\n")

print(f"Report generated: {report_file}")
'

echo "All benchmarks complete!"
echo "To view the full report, open the generated report file in the benchmarks/results/reports directory."
