from __future__ import annotations
from pydantic import BaseModel
from typing import Literal
from datetime import datetime

# Map Validated row keys vs columns of 'tmp_log' table in DB
SCHEMAS_MAP: dict = {
	'benchmark_id': "benchmark_id",
	'binary_id': "binary_id",
	'DateTime': "date_time",
	'InputPath': "input_path",
	'Width': "width",
	'Height': "height",
	'StrideBytes': "stride_bytes",
	'MPix': "mpix",
	# '': cold_start_length # not yet present in the binary logs
	'N_Iters': "hot_loop_length",
	'StatsLayout': "stats_layout",
	'ColdStart_ms': "cold_start_ms",
	'AvgLoop_ms': "hot_loop_avg_ms",
	'BestTime_ms': "best_time_ms",
	'MaxPerf_MPixSec': "max_perf_mpix_sec",
	'DetectedNcomponents': "detected_n_components",
	'ForegroundArea': "foreground_area",
	'DetectedNruns': "detected_n_runs",
	'RefPath': "ref_path",
	'RefNcomponents': "ref_n_components",
	'Validation': "validation",
	'RefStatsPath': "ref_stats_path",
	'StatsValidation': "stats_validation"
}

class BaseMetrics(BaseModel):
	DateTime: datetime
	InputPath: str
	Width: int
	Height: int
	StrideBytes: int
	MPix: float
	N_Iters: int
	StatsLayout: Literal["SKIPPED", "BASE", "BASE+M1", "BASE+M1+M2"]
	ColdStart_ms: float
	AvgLoop_ms: float
	BestTime_ms: float
	MaxPerf_MPixSec: float
	DetectedNcomponents: int

class OpenCVmetrics(BaseMetrics):
	pass
	
class FlyRLECCLmetrics(BaseMetrics):
	ForegroundArea: int
	DetectedNruns: int
	RefPath: str
	RefNcomponents: int
	Validation: Literal["SKIPPED", "PASSED", "FAILED"]
	RefStatsPath: str
	StatsValidation: Literal["SKIPPED", "PASSED", "FAILED"]

class Binary(BaseModel):
	lib_name: Literal["FlyRLECCL", "OpenCV"]
	lib_version_tag: str
	compiler_flags: str
	git_commit_hash: str
	description: str
	csv_name: str

class Environment(BaseModel):
	env_name: str
	cpu_model: str
	cpu_ghz: float
	ram_gb: float
	os_info: str
	notes: str
	
class Benchmark(BaseModel):
	username: str
	dataset: str
	environment: Environment
	img_random_order: bool
	iter_count: int
	start_at: datetime
	end_at: datetime
	binaries: list[Binary]

# Export classes, which other modules will then import.
__all__ = ["Benchmark", "Binary", "Environment", "FlyRLECCLmetrics", "OpenCVmetrics"]