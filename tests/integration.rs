use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

#[tokio::test]
async fn test_non_tls_forwarding() {
    let target = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let target_addr = target.local_addr().unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let listen_addr = listener.local_addr().unwrap();

    tokio::spawn(async move {
        rport::tunnel::start(listener, &target_addr.to_string()).await.unwrap();
    });

    let (mut target_stream, _) = target.accept().await.unwrap();
    let mut client = TcpStream::connect(listen_addr).await.unwrap();

    client.write_all(b"hello").await.unwrap();
    let mut buf = [0u8; 5];
    target_stream.read_exact(&mut buf).await.unwrap();
    assert_eq!(&buf, b"hello");

    target_stream.write_all(b"world").await.unwrap();
    let mut buf = [0u8; 5];
    client.read_exact(&mut buf).await.unwrap();
    assert_eq!(&buf, b"world");
}