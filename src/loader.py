from __future__ import annotations
import psycopg
from psycopg import sql
from pydantic import BaseModel
from pathlib import Path
from datetime import datetime
from settings import settings
from .schemas import Benchmark, Binary, Environment, SCHEMAS_MAP

def _registrate_binary(cur: psycopg.Cursor, binary: Binary) -> int:
	"""
	Ensures the library exists and upserts the binary version, returning its binary_id.
	"""
	# 1. Ensure library is registered
	cur.execute(
		"""
		SELECT lib_id
		FROM libs 
		WHERE lib_name = %s;
		""",
		(binary.lib_name,)
	)
	
	db_lib = cur.fetchone()
	
	if not db_lib:
		#logger.error(f"Binary configuration in '{json_filename}' file is impossible to register, bacause the library '{binary.lib_name}' hasn't registrated yet.")
		raise ValueError(f"Binary configuration mismatch: the library '{binary.lib_name}' hasn't registrated yet.")		
	
	lib_id = db_lib[0]
	
	# 2. Upsert binary version & optimization flags
	cur.execute(
		"""
		SELECT binary_id, lib_version_tag, compiler_flags, description
		FROM binaries
		WHERE lib_id = %s AND git_commit_hash = %s;
		""",
		(lib_id, binary.git_commit_hash,)
	)
	
	db_binary = cur.fetchone()
	
	if db_binary:
		db_binary_id, db_lib_version_tag, db_compiler_flags, db_description = db_binary
		
		# Strict validation: prevent silent hardware specification changes
		if (db_lib_version_tag == binary.lib_version_tag and
			db_compiler_flags == binary.compiler_flags and
			db_description == binary.description):
			return db_binary_id
		
		#logger.error(f"Binary configuration mismatch with the already registerd in DB binary which has the same git_commit_hash for lib '{binary.lib_name}'.")
		raise ValueError(f"Binary configuration mismatch for the library '{binary.lib_name}'.")
	
	cur.execute(
		"""
		INSERT INTO binaries (lib_id, lib_version_tag, compiler_flags, git_commit_hash, description)
		VALUES (%s, %s, %s, %s, %s)
		RETURNING binary_id;
		""",
		(lib_id, binary.lib_version_tag, binary.compiler_flags, binary.git_commit_hash, binary.description,)
	)
	return cur.fetchone()[0]

def _registrate_environment(cur: psycopg.Cursor, env: Environment) -> int:
	"""
	Finds existing environment by name and verifies specs, 
	or registers a new one if it doesn't exist. Fails if specs mismatch.
	"""	
	cur.execute(
		"""
		SELECT environment_id, cpu_model, cpu_ghz, ram_gb, os_info, notes
		FROM environments 
		WHERE env_name = %s;
		""",
		(env.env_name,)
	)
	
	db_env = cur.fetchone()
	
	if db_env:
		db_id, db_cpu_model, db_cpu_ghz, db_ram_gb, db_os_info, db_notes = db_env
		
		# Strict validation: prevent silent hardware specification changes
		if (db_cpu_model == env.cpu_model and 
			abs(db_cpu_ghz - env.cpu_ghz) < 1e-5 and 
			abs(db_ram_gb - env.ram_gb) < 1e-5 and
			(not env.os_info or db_os_info == env.os_info) and
			(not env.notes or db_notes == env.notes)):
			return db_id
		
		raise ValueError(f"Environment configuration mismatch.")
	
	cur.execute(
		"""
		INSERT INTO environments (env_name, cpu_model, cpu_ghz, ram_gb, os_info, notes)
		VALUES (%s, %s, %s, %s, %s, %s)
		RETURNING environment_id;
		""",
		(env.env_name, env.cpu_model, env.cpu_ghz, env.ram_gb, env.os_info, env.notes,)
	)
	return cur.fetchone()[0]

def _registrate_benchmark(cur: psycopg.Cursor, benchmark: Benchmark) -> int:
	"""
	Registers a benchmark run or retrieves its existing ID if it was already processed.
	Ensures that identical benchmark runs aren't duplicated blindly.
	"""
	# 1. Ensure user is registered
	if benchmark.username:
		cur.execute(
			"""
			SELECT user_id
			FROM users 
			WHERE username = %s;
			""",
			(benchmark.username,)
		)
		db_user = cur.fetchone()
		if not db_user:
			raise ValueError(f"Benchmark configuration mismatch: the user '{benchmark.username}' is not yet registered.")		
		user_id = db_user[0]
	else:
		user_id = None
	
	
	# 2. Environment registration
	env_id = _registrate_environment(cur, benchmark.environment)
	
	# 3. Benchmark registration
	cur.execute(
		"""
		SELECT benchmark_id
		FROM benchmarks 
		WHERE environment_id = %s AND start_at = %s AND end_at = %s;
		""",
		(env_id, benchmark.start_at, benchmark.end_at)
	)
	
	if cur.fetchone():
		raise ValueError(f"Such benchmark is already registrated and its results was saved in DB.")
		
	cur.execute(
		"""
		INSERT INTO benchmarks (user_id, environment_id, img_random_order, iter_count, start_at)
		VALUES (%s, %s, %s, %s, %s)
		RETURNING benchmark_id;
		""",
		(user_id, env_id, benchmark.img_random_order, benchmark.iter_count, benchmark.start_at,)
	)
	
	benchmark_id = cur.fetchone()[0]
	
	if benchmark.dataset:
		cur.execute(
			"""
			INSERT INTO datasets (name)
			VALUES (%s)
			ON CONFLICT (name) DO UPDATE
			SET name = EXCLUDED.name
			RETURNING dataset_id;
			""",
			(benchmark.dataset,)
		)
		dataset_id = cur.fetchone()[0]
		
		cur.execute(
			"""
			INSERT INTO benchmark_to_dataset (benchmark_id, dataset_id)
			VALUES (%s, %s)
			ON CONFLICT (benchmark_id, dataset_id) DO NOTHING
			""",
			(benchmark_id, dataset_id,)
		)
	
	return benchmark_id

def get_metrics_foreign_ids(benchmark_pasport: Benchmark) -> tuple(int, dict):
	with psycopg.connect(str(settings.DATABASE_URL)) as conn:
		with conn.cursor() as cur:
			
			benchmark_id = _registrate_benchmark( cur, benchmark_pasport)
			
			binary_ids = {}
			for binary in benchmark_pasport.binaries:
				 binary_ids[binary.csv_name] = _registrate_binary(cur, binary)
	
	return benchmark_id, binary_ids
	
def load_data_to_db(csv_headers: list, rows_to_insert: list[dict]) -> None:
	# Guarder
	if not rows_to_insert:
		return
	
	# 1. Take the keys from the first dictionary as a list of column names
	sql_column_names = [SCHEMAS_MAP[key] for key in csv_headers]
	
	# 2. Dynamically construct parts of an SQL query using `psycopg.sql` (protection against SQL injection)
	# Column names
	sql_columns = sql.SQL(', ').join(sql.Identifier(col) for col in sql_column_names)
	
	# Placeholders for values ​​(%s, %s, ...) corresponding to the number of columns
	sql_placeholders = sql.SQL(', ').join(sql.Placeholder() for _ in sql_column_names)
	
	# Assembling the final request: INSERT INTO tmp_log (col1, col2) VALUES (%s, %s)
	insert_query = sql.SQL("INSERT INTO tmp_log ({}) VALUES ({})").format(
		sql_columns,
		sql_placeholders
	)
	
	# 3. Convert a list of dictionaries into a list of tuples, maintaining the same strict column order
	tuples_to_insert = [
		tuple(row[col] for col in csv_headers) for row in rows_to_insert
	]
	
	with psycopg.connect(str(settings.DATABASE_URL)) as conn:
		with conn.cursor() as cur:
			cur.executemany(insert_query, tuples_to_insert)

def finalize_etl(benchmark_id: int, end_at: datetime) -> None:
	with psycopg.connect(str(settings.DATABASE_URL)) as conn:
		with conn.cursor() as cur:
			cur.execute(
				"""
				UPDATE benchmarks 
				SET end_at = %s 
				WHERE benchmark_id = %s;
				""",
				(end_at, benchmark_id)
			)