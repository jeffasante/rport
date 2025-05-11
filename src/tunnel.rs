// scr/tunnel.rs 
/* an async function to forward data bidirectionally between a local client and a remote target. */

use log::{debug, error, info};
use tokio::io::{self, AsyncRead, AsyncWrite, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

pub async fn start(listener: TcpListener, target: &str) -> io::Result<()> {
    // Listens for incoming connections and spawns a task per client.
    loop {
        let (client, client_addr) = listener.accept().await?;
        info!("New connection from {}", client_addr);

        let target = target.to_string();
        tokio::spawn(async move {
            if let Err(e) = handle_connection(client, &target).await {
                error!("Connection error for {}: {}", client_addr, e);
            }
        });
    }
}

pub async fn handle_connection<T: AsyncRead + AsyncWrite + Unpin>(
    // Connects to the target and uses tokio::io::copy_bidirectional (via split streams) for efficient data transfer.
    client: T,
    target: &str,
) -> io::Result<()> {
    debug!("Attempting to connect to target {}", target);
    let mut target_stream = TcpStream::connect(target).await?;
    info!("Connected to target {}", target);

    debug!("Starting bidirectional copy");
    // Bidirectional copy between client and target
    let (mut client_reader, mut client_writer) = io::split(client);
    let (mut target_reader, mut target_writer) = target_stream.split();

    let client_to_target = async {
        debug!("Copying client to target");
        let result = io::copy(&mut client_reader, &mut target_writer).await;
        debug!("Client to target copy done: {:?}", result);
        target_writer.shutdown().await
    };

    let target_to_client = async {
        debug!("Copying target to client");
        let result = io::copy(&mut target_reader, &mut client_writer).await;
        debug!("Target to client copy done: {:?}", result);
        client_writer.shutdown().await
    };

    // Run both directions concurrently
    debug!("Joining copy tasks");
    tokio::try_join!(client_to_target, target_to_client)?;
    debug!("Connection handling complete");
    Ok(())
}


async fn handle_tls_connection<T: AsyncRead + AsyncWrite + Unpin>(
    client: T,
    target: &str,
) -> io::Result<()> {
    // Implement similar logic as in tunnel.rs handle_connection
    let target_stream = TcpStream::connect(target).await?;
    info!("Connected to target {}", target);

    // Bidirectional copy between client and target
    let (mut client_reader, mut client_writer) = io::split(client);
    let (mut target_reader, mut target_writer) = io::split(target_stream);

    let client_to_target = async {
        io::copy(&mut client_reader, &mut target_writer).await?;
        target_writer.shutdown().await
    };

    let target_to_client = async {
        io::copy(&mut target_reader, &mut client_writer).await?;
        client_writer.shutdown().await
    };

    // Run both directions concurrently
    tokio::try_join!(client_to_target, target_to_client)?;
    debug!("Connection closed");

    Ok(())
}