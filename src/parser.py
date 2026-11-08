import json
from pydantic import ValidationError
from pathlib import Path
from settings import settings
from .logger import logger
from .schemas import *

def parse_json(benchmark_name: str):
	json_file_path = settings.STAGING_DIR / benchmark_name / f"{benchmark_name}.json"
	
	if not json_file_path.exists() or not json_file_path.is_file():
		logger.error(
			f"JSON File file was not found",
			extra={
				"benchmark_name": benchmark_name,
				"json_filename": json_file_path.name
			}
		)
		return None
		
	try:
		# 1. PARSING: Reading a file and converting a JSON string into a Python dictionary
		with open(json_file_path, 'r', encoding='utf-8') as f:
			json_dict = json.load(f)
		
		# 2. VALIDATION: Checking whether the parsed JSON conforms to class structure
		benchmark_pasport = Benchmark(**json_dict)
		
		# 2. VALIDATION: Checking whether the parsed JSON conforms to class structure
		if not benchmark_pasport.start_at:
			raise ValueError(f"Invalid benchmark configuration: benchmark parameter 'start_at' not specified")
		if not benchmark_pasport.end_at:
			raise ValueError(f"Invalid benchmark configuration: benchmark parameter 'end_at' not specified")
		if benchmark_pasport.start_at >= benchmark_pasport.end_at:
			raise ValueError(f"Invalid combination of configuration parameters of the benchmark: 'start_at' >= 'end_at'")
		
		logger.success(f"JSON file '{json_file_path.name}' from the directory '{benchmark_name}' has been read and validated",)
		return benchmark_pasport
	
	except json.JSONDecodeError as e:
		logger.error(
			f"JSON file contains an invalid JSON",
			extra={
				"benchmark_name": benchmark_name,
				"json_filename": json_file_path.name,
				"syntax error": str(e)
			}
		)
	except ValidationError as e:
		logger.error(
			f"The JSON structure in the JSON file does not conform to the schema",
			extra={
				"benchmark_name": benchmark_name,
				"json_filename": json_file_path.name,
				"structural error": str(e)
			}
		)
	except ValueError as e:
		logger.error(
			f"{e}",
			extra={
				"benchmark_name": benchmark_name,
				"json_filename": json_file_path.name
			}
		)
		
	return None