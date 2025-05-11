// clap to parse command-line arguments for the listen address, target address, and optional TLS certificate/key.
/* This defines the CLI interface (--listen, --target, --tls-cert, --tls-key).
    The SocketAddr type ensures --listen is a valid address. TLS args are optional and mutually required (enforced by requires).
 */
use clap::Parser;
use std::net::SocketAddr;

#[derive(Parser, Debug)]
#[command(about = "A high-performance TCP port-forwarder written in Rust")]
pub struct Config {
    /// Local address to listen on (e.g., 0.0.0.0:9009)
    #[arg(long, default_value = "0.0.0.0:9309")]
    pub listen: SocketAddr,

    /// Remote address to forward to (e.g., example.com:80)
    #[arg(long)]
    pub target: String,

    /// Path to TLS certificate (optional)
    #[arg(long)]
    pub tls_cert: Option<String>,

    /// Path to TLS private key (optional)
    #[arg(long, requires = "tls_cert")]
    pub tls_key: Option<String>,
}

pub fn parse() -> Config {
    Config::parse()
}


// ./target/release/rport --listen 127.0.0.1:9309 --target 127.0.0.1:8080
// RUST_LOG=debug ./target/release/rport --listen 127.0.0.1:9309 --target 127.0.0.1:8080
// curl -v http://127.0.2080