// scr/tls.rs 

use std::fs::File;
use std::io::BufReader;
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use rustls::ServerConfig;
use tokio_rustls::TlsAcceptor;

pub fn is_enabled() -> bool {
    cfg!(feature = "tls")
}

pub fn load_tls_config(cert_path: &str, key_path: &str) -> std::io::Result<TlsAcceptor> {
    let certs = {
        let file = File::open(cert_path)?;
        let mut reader = BufReader::new(file);
        rustls_pemfile::certs(&mut reader)
            .collect::<Result<Vec<CertificateDer<'static>>, _>>()
            .map_err(|_| std::io::Error::new(std::io::ErrorKind::InvalidData, "Invalid cert"))?
    };
    let key = {
        let file = File::open(key_path)?;
        let mut reader = BufReader::new(file);
        let keys = rustls_pemfile::pkcs8_private_keys(&mut reader)
            .map(|result| result.map(PrivateKeyDer::Pkcs8))
            .collect::<Result<Vec<PrivateKeyDer<'static>>, _>>()
            .map_err(|_| std::io::Error::new(std::io::ErrorKind::InvalidData, "Invalid key"))?;
        keys.into_iter()
            .next()
            .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidData, "No key found"))?
    };

    let config = ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certs, key)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    Ok(TlsAcceptor::from(std::sync::Arc::new(config)))
}