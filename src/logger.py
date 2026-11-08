import sys
from loguru import logger
from settings import settings

def setup_logger() -> None:
    """Configure a global logger for the console and a JSON file."""
    # Remove the default handler loguru
    logger.remove()

	# Create a folder for logs, if it doesn't already exist
    settings.LOGS_DIR.mkdir(parents=True, exist_ok=True)
    
	# Create a folder for logs, if it doesn't already exist
    settings.LOGS_DIR.mkdir(parents=True, exist_ok=True)

    # Constructing the full path to the log file
    log_file_path = settings.LOGS_DIR / "etl.log"

    # 1. Add log output to the console
    logger.add(
        sys.stdout,
        level="INFO",
        format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{line}</cyan> - <level>{message}</level>"
    )

    # 2. Add log output into the log file
    logger.add(
        log_file_path,
        level="DEBUG",
        serialize=True,  # Automatically packages into JSON
        rotation="10 MB", # Log rotation when size limit is exceeded
        encoding="utf-8"
    )
	
setup_logger()

# Export a configured logger, which other modules will then import.
__all__ = ["logger"]