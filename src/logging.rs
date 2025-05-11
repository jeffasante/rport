/* Connection and error logging */

use env_logger::{Builder, Env};
use log::LevelFilter;

pub fn init() {
    Builder::from_env(Env::default().default_filter_or("info"))
    .filter_module("rport", LevelFilter::Info)
    .init();
}