import click
from pathlib import Path
import shutil
from settings import settings
from src.logger import logger
from src.parser import parse_json
from src.data_validator import validate_csv_schema, validate_csv_data
from src.loader import get_metrics_foreign_ids, load_data_to_db, finalize_etl
from src.schemas import Benchmark
#import os
#os.environ["PGSSLCERT"] = ""
#os.environ["PGSSLKEY"] = ""

@click.command()
@click.option(
	'--source', 
	type=click.Choice(['local', 's3', 'api']), 
	default='local', 
	help='Type of data source'
)
@click.option(
	'--benchmark-list', 
	default=None, 
	help='Comma separated list of folders with benchmark data files (if omitted, processes all)'
)
def main(source: str, benchmark_list: str):
	"""ETL Pipeline for FlyRLECCL benchmark logs ingestion."""
	# Parse the list of folders if it is provided as a comma-separated string
	benchmarks = {b.strip() for b in benchmark_list.split(',')} if benchmark_list else set()
	
	if source != 'local':
		logger.info(f"Option '{source}' isn't supported yet")
		return
	
	subdirs = {p.name for p in settings.STAGING_DIR.iterdir() if p.is_dir()}
	benchmarks = benchmarks & subdirs if benchmarks else subdirs
	
	logger.info(
		f"ETL Pipeline is started",
		extra={
			"source": source,
			"data_path": settings.STAGING_DIR,
			"benchmark_list_to_process": benchmarks
		}
	)
	
	if not benchmarks:
		logger.success(f"ETL Pipeline is finished: {len(benchmarks)} benchmarks have processed")
		return
	
	benchmark_count = 0
	csv_headers = {}
	for benchmark_name in benchmarks:
		logger.info(f"Processing benchmark bundle: {benchmark_name}")

		# Step 1: Parse and validate JSON passport
		benchmark_passport = parse_json(benchmark_name)
		if not benchmark_passport: continue
		
		# Step 2: Validate CSV headers
		try:
			for binary_passport in benchmark_passport.binaries:
				csv_headers[binary_passport.csv_name] = validate_csv_schema(binary_passport, benchmark_name)
		except FileNotFoundError as e:
			logger.exception(
				f"{e}",
				extra={
					"benchmark_name": benchmark_name,
					"lib_name": binary_passport.lib_name,
					"csv_filename": binary_passport.csv_name
				}
			)
			continue			
		except ValueError as e:
			logger.exception(
				f"{e}",
				extra={
					"benchmark_name": benchmark_name,
					"lib_name": binary_passport.lib_name,
					"csv_filename": binary_passport.csv_name
				}
			)
		except Exception as e:
			logger.exception(
				f"Critical error while reading CSV: {e}",
				extra={
					"benchmark_name": benchmark_name,
					"lib_name": binary_passport.lib_name,
					"csv_filename": binary_passport.csv_name
				}
			)
			continue
			
		# Step 3: Registrate benchmark into PostgreSQL
		try:
			benchmark_id, binary_map_ids = get_metrics_foreign_ids(benchmark_passport)
			
			logger.success(f"All required IDs {binary_map_ids} for benchmark ID '{benchmark_id}' for data in the directory '{benchmark_name}' has been recieved from DB",)
		
		except ValueError as e:
			logger.exception(
				f"Critical error. Benchmark registration failed: {e}",
				extra={
					"benchmark_name": benchmark_name
				}
			)
			continue
			
		
		for binary_passport in benchmark_passport.binaries:
			# Step 4: Validate CSV rows
			csv_file_path = settings.STAGING_DIR / benchmark_name / binary_passport.csv_name
			valid_data = validate_csv_data(benchmark_id, binary_map_ids[binary_passport.csv_name], binary_passport.lib_name, csv_file_path)
			
			logger.success(f"Data in the file '{csv_file_path.name}' from the directory '{benchmark_name}' has been read and validated",)
			
			# Step 5: Load CSV rows
			if valid_data:
				valid_data_headers = ["benchmark_id", "binary_id", *csv_headers[binary_passport.csv_name]] 
				load_data_to_db(valid_data_headers, valid_data)
			else:
				logger.warning(
					f"No valid rows found in csv-file.",
					extra={
						"benchmark_name": benchmark_name,
						"lib_name": binary_passport.lib_name,
						"csv_filename": binary_passport.csv_name
					}
				)		
				
			logger.success(f"All valid data from the file '{csv_file_path.name}' from the directory '{benchmark_name}' has been inserted to DB",)
			
		# Step 6: Set end_at. This update instantly triggers `trg_benchmark_finished` and sets all the ETL magic in motion within the database.
		finalize_etl(benchmark_id, benchmark_passport.end_at)		
		
		
		# Step 7: Archive the benchmark
		benchmark_dir = settings.STAGING_DIR / benchmark_name
		archive_dir = settings.ARCHIVE_DIR / benchmark_name
		shutil.move(benchmark_dir, archive_dir)
		
		logger.success(f"ETL Pipeline for benchmark '{benchmark_name}' is finished",)
		
		benchmark_count += 1
		
	logger.success(f"ETL Pipeline is finished: {benchmark_count} from {len(benchmarks)} benchmarks have been processed")

if __name__ == '__main__':
	main()