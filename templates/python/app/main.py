"""{{PROJECT_NAME}} — Entry point."""
import sys
import logging

from app.orchestrator import run_pipeline


def setup_logging() -> None:
    """Configure structured JSON logging."""
    logging.basicConfig(
        level=logging.INFO,
        format='{"time":"%(asctime)s","level":"%(levelname)s","module":"%(name)s","msg":"%(message)s"}',
        handlers=[logging.StreamHandler(sys.stdout)],
    )


def main() -> None:
    setup_logging()
    logger = logging.getLogger(__name__)
    logger.info("Starting {{PROJECT_NAME}}")
    run_pipeline()


if __name__ == "__main__":
    main()
