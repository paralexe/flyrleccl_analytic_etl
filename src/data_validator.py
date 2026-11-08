from __future__ import annotations
import csv
from pathlib import Path
from pydantic import ValidationError
from settings import settings
from .logger import logger
from .schemas import Binary, OpenCVmetrics, FlyRLECCLmetrics

# A registry mapping library names from JSON to their corresponding Pydantic metrics models
METRICS_MAP = {
	"opencv": OpenCVmetrics,
	"flyrleccl": FlyRLECCLmetrics,
}

def get_metrics_model(lib_name: str):
	"""Dynamically returns a metrics class based on the library name"""
	model_class = METRICS_MAP.get(lib_name.lower())
	if not model_class:
		raise ValueError(f"Неизвестная библиотека в JSON-паспорте: {lib_name}")
	return model_class

def validate_csv_schema(binary: Binary, benchmark_name: str) -> list:
	csv_file_path = settings.STAGING_DIR / benchmark_name / binary.csv_name
	if not csv_file_path.exists() or not csv_file_path.is_file():
		raise FileNotFoundError(f"The CSV file was not found in the staging dir.")

	# Obtain the Pydantic metrics class and the expected set of csv columns
	metrics_model = get_metrics_model(binary.lib_name)
	expected_columns = list(metrics_model.model_fields.keys())

	with open(csv_file_path, mode='r', encoding='utf-8') as f:
		reader = csv.DictReader(f)
		file_headers = reader.fieldnames or []
		# Header check (Schema Enforcement)
		if not set(expected_columns).issubset(set(file_headers)):
			raise Exception(f"Schema error in CSV file: headers do not match the model.")
	
	logger.success(f"The header line of the file '{binary.csv_name}' from the directory '{benchmark_name}' has been read and validated",)
	return reader.fieldnames

def validate_csv_data(benchmark_id: int, binary_id: int, lib_name: str, csv_file_path: Path) -> list[dict]:
	with open(csv_file_path, mode='r', encoding='utf-8') as f:
		reader = csv.DictReader(f)
		# Line-by-line data type validation
		valid_rows = []
		invalid_rows = []
		for row_idx, row in enumerate(reader, start=2):
			try:
				# Pydantic will automatically coerce types and validate constraints (Literal, gt=0, etc.)
				metrics_model = METRICS_MAP.get(lib_name.lower())
				validated_metric = metrics_model(**row)

				valid_entry = {"benchmark_id": benchmark_id, "binary_id": binary_id, **validated_metric.model_dump()}
				valid_rows.append(valid_entry)
			except ValidationError as err:
				# Save the corrupted string along with the reason for the error to the "Hell" folder
				error_entry = {"row_number": row_idx, **row, "validation_error": str(err)}
				invalid_rows.append(error_entry)
	
	# 4. Open the file for writing and write to it using DictWriter
	if 	invalid_rows:
		csv_invalid_filename = csv_file_path.stem + '_errors.csv'
		csv_invalid_file_path = csv_file_path.parent / csv_invalid_filename

		fieldnames = list(invalid_rows[0].keys())
		
		with open(csv_invalid_file_path, mode='w', encoding='utf-8', newline='') as f:
			writer = csv.DictWriter(f, fieldnames=fieldnames)
			writer.writeheader()          # wrote down the header (headings)
			writer.writerows(invalid_rows) # Recorded ALL broken lines at once

		logger.warning(
			f"Found {len(invalid_rows)} invalid rows in {csv_file_path.name}. Error report saved to {csv_invalid_filename}"
		)

	return valid_rows