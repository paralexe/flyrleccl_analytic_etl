from functools import lru_cache
from pathlib import Path
from typing import Literal
from pydantic import Field, PostgresDsn
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
	"""Application configuration management.
	Automatically reads environment variables and the .env file with strict typing.
	"""
	
	# Application execution environment
	ENVIRONMENT: Literal["development", "staging", "production"] = Field(
		default="development",
		validation_alias="ENVIRONMENT"
	)
	DEBUG: bool = Field(default=False, validation_alias="DEBUG")
	
	# Project directories configuration
	# BASE_DIR points to the directory where config.py is located
	BASE_DIR: Path = Path(__file__).resolve().parent
	
	LOGS_DIR: Path = BASE_DIR / "logs"
	
	# DATA_DIR can be overridden via .env if data is stored elsewhere (e.g., /app/data)
	DATA_DIR: Path = BASE_DIR / "data"
	
	STAGING_DIR: Path = DATA_DIR / "staging"
	ARCHIVE_DIR: Path = DATA_DIR / "archive"
	
	# Database settings (Neon / PostgreSQL)
	DATABASE_URL: PostgresDsn = Field(
		...,
		validation_alias="DATABASE_URL",
		description="PostgreSQL connection string (e.g., Neon DB)"
	)
	
	# Connection pool parameters for production load optimization
	DB_POOL_SIZE: int = Field(default=5, validation_alias="DB_POOL_SIZE")
	DB_MAX_OVERFLOW: int = Field(default=10, validation_alias="DB_MAX_OVERFLOW")
	DB_POOL_TIMEOUT: int = Field(default=30, validation_alias="DB_POOL_TIMEOUT")
	
	# Pydantic settings configuration
	model_config = SettingsConfigDict(
		env_file=".env",
		env_file_encoding="utf-8",
		case_sensitive=True,
	extra="ignore"  # Ignore extraneous environment variables in .env
	)


@lru_cache
def get_settings() -> Settings:
	"""Returns a cached settings instance.
	Using lru_cache ensures the .env file is read and validated
	exactly once upon application startup.
	"""
	return Settings()


# Export a ready-to-use settings object to import across other modules
settings = get_settings()