/* Tie everything together: parse CLI, initialize logging, and start the tunnel. */
// mod rport;

use log::error;
use tokio::io::{AsyncRead, AsyncWrite};
use rport::{config::parse, logging::init, tunnel::start};
use tokio::net::TcpListener;

#[cfg(feature = "tls")]
use tokio_rustls::TlsAcceptor;
#[cfg(feature = "tls")]
use rport::tls;

#[tokio::main]
async fn main() {
    init();

    let config = parse();
    let listener = match TcpListener::bind(config.listen).await {
        Ok(listener) => listener,
        Err(e) => {
            error!("Failed to bind to {}: {}", config.listen, e);
            return;
        }
    };

    #[cfg(feature = "tls")]
    let tls_acceptor = if let (Some(cert), Some(key)) = (&config.tls_cert, &config.tls_key) {
        match rport::tls::load_tls_config(cert, key) {
            Ok(acceptor) => Some(acceptor),
            Err(e) => {
                error!("Failed to load TLS config: {}", e);
                return;
            }
        }
    } else {
        None
    };

    #[cfg(feature = "tls")]
    {
        if let Some(acceptor) = tls_acceptor {
            log::info!("Starting TLS forwarding");
            if let Err(e) = start_tls(listener, &config.target, acceptor).await {
                error!("TLS tunnel error: {}", e);
            }
            return;
        }
    }

    log::info!("Starting non-TLS forwarding");
    if let Err(e) = start(listener, &config.target).await {
        error!("Tunnel error: {}", e);
    }
}

#[cfg(feature = "tls")]
async fn start_tls(
    listener: TcpListener,
    target: &str,
    acceptor: TlsAcceptor,
) -> std::io::Result<()> {

    loop {
        let (client, client_addr) = listener.accept().await?;
        log::info!("New TLS connection from {}", client_addr);

        let target = target.to_string();
        let acceptor = acceptor.clone();
        tokio::spawn(async move {
            let tls_stream = match acceptor.accept(client).await {
                Ok(stream) => stream,
                Err(e) => {
                    log::error!("TLS handshake failed for {}: {}", client_addr, e);
                    return;
                }
            };
            if let Err(e) = handle_tls_connection(tls_stream, &target).await {
                log::error!("TLS connection error for {}: {}", client_addr, e);
            }
        });
    }
}

#[cfg(feature = "tls")]
async fn handle_tls_connection<T: AsyncRead + AsyncWrite + Unpin>(
    client: T,
    target: &str,
) -> std::io::Result<()> {
    rport::tunnel::handle_connection(client, target).await
}