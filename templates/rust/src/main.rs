//! {{PROJECT_NAME}} — Entry point.

mod modules;
mod contracts;
mod orchestrator;

use log::info;

fn main() {
    env_logger::init();
    info!("Starting {{PROJECT_NAME}}");
    orchestrator::run_pipeline();
}
