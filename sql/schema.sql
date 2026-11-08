-- 1. Roles catalog (RBAC)
CREATE TABLE IF NOT EXISTS roles (
	role_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_code VARCHAR(32) UNIQUE NOT NULL, -- 'ADMIN', 'ENGINEER', 'VIEWER'
    description TEXT
);

-- Insert roles
INSERT INTO roles (role_code, description) VALUES
('ADMIN', 'Full system access and management'),
('ENGINEER', 'Can run benchmarks and ingest raw data'),
('VIEWER', 'Read-only access to dashboards and metrics')
ON CONFLICT (role_code) DO NOTHING;

-- 2. User accounts
CREATE TABLE IF NOT EXISTS users (
    user_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username VARCHAR(64) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role_id INT REFERENCES roles(role_id) ON DELETE RESTRICT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Dataset catalogue (YACCLAB Medical, Text, Objects)
CREATE TABLE IF NOT EXISTS datasets (
    dataset_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
	url VARCHAR(255),
    description TEXT
);

-- 4. Information about images (dataset elements)
CREATE TABLE IF NOT EXISTS images (
    image_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dataset_id INT REFERENCES datasets(dataset_id) ON DELETE CASCADE,
    filename VARCHAR(255) NOT NULL,
    width INT NOT NULL CHECK (width > 0),
    height INT NOT NULL CHECK (height > 0),
	stride_bytes INT NOT NULL,
    component_count INT,
	foreground_area INT,
    runs_count INT,

    -- Enforces that stride is always greater than or equal to width
    CONSTRAINT chk_stride_dimensions CHECK (stride_bytes >= width),
	-- Creating compound indexes to speed up searching and filtering
	CONSTRAINT unique_dataset_vs_filename UNIQUE (dataset_id, filename)
);

-- 5. Libraries names
CREATE TABLE IF NOT EXISTS libs (
	lib_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	lib_name VARCHAR(32) UNIQUE NOT NULL        -- 'FlyRLECCL', 'OpenCV'
);

-- Insert library names
INSERT INTO libs (lib_name) VALUES
	('FlyRLECCL'),
	('OpenCV')
ON CONFLICT (lib_name) DO NOTHING;

-- 6. Binary versions and compilation parameters (optimization flags, architecture)
CREATE TABLE IF NOT EXISTS binaries (
    binary_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lib_id INT NOT NULL REFERENCES libs(lib_id) ON DELETE CASCADE,
	lib_version_tag VARCHAR(100),            -- for example, 'v1.2.0-avx2'
    compiler_flags VARCHAR(255),         -- for example, '-O3 -march=native -std=c99'
    git_commit_hash VARCHAR(40),
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	
	-- Creating compound indexes to speed up searching and filtering
	CONSTRAINT unique_binary UNIQUE (lib_id, git_commit_hash)	
);

-- Insert binaries
INSERT INTO binaries (lib_id, lib_version_tag, compiler_flags, git_commit_hash, description) 
SELECT
	libs.lib_id,
	'v0.0.1-x64',
	'-std=gnu99 -Wall -Wextra -Wpedantic -D__USE_MINGW_ANSI_STDIO=1 -O3 -DNDEBUG',
	'b6ca4f9',
	'flyrleccl_2d8c_inz_c16u_o32u_scalar_demo.exe'
FROM libs 
WHERE lib_name = 'FlyRLECCL'
ON CONFLICT (lib_id, git_commit_hash) DO NOTHING;

INSERT INTO binaries (lib_id, lib_version_tag, compiler_flags, git_commit_hash, description) 
SELECT
	libs.lib_id,
	'v4.5.5-x64',
	'-std=gnu99 -Wall -Wextra -Wpedantic -D__USE_MINGW_ANSI_STDIO=1 -O3 -DNDEBUG',
	'b6ca4f9',
	'fly_opencv_2d8c_demo.exe'
FROM libs 
WHERE lib_name = 'OpenCV'
ON CONFLICT (lib_id, git_commit_hash) DO NOTHING;

-- 7. The environment in which the test was run (hardware, OS, configuration)
CREATE TABLE IF NOT EXISTS environments (
    environment_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    env_name VARCHAR(100) UNIQUE NOT NULL,      -- for example, 'Win7-DevMachine', 'Linux-CI-Runner'
    cpu_model VARCHAR(255),
    cpu_ghz DOUBLE PRECISION,            -- CPU frequency
	ram_gb DOUBLE PRECISION,
    os_info VARCHAR(100),
    notes TEXT
);

-- Insert environment
INSERT INTO environments (env_name, cpu_model, cpu_ghz, ram_gb, os_info)
VALUES ('Win7-2.00GHz', 'Intel(R) Core(TM) i7-2630QM', 2.0, 6.0, 'Windows 7 Home')
ON CONFLICT (env_name) DO NOTHING;

-- 8. Types of statistics layout (what statistics metrics are calculated)
CREATE TABLE IF NOT EXISTS stats_layouts (
    stats_layout_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	name VARCHAR(32) UNIQUE NOT NULL, -- 'SKIPPED', 'BASE', 'BASE+M1', 'BASE+M1+M2'
	base_stats BOOLEAN DEFAULT FALSE,
	m1 BOOLEAN DEFAULT FALSE,
	m2 BOOLEAN DEFAULT FALSE,

	-- Creating compound indexes to speed up searching and filtering
	CONSTRAINT unique_stats_layout UNIQUE (name, base_stats, m1, m2)
);

-- Insert roles
INSERT INTO stats_layouts (name, base_stats, m1, m2) VALUES
('SKIPPED', FALSE, FALSE, FALSE),
('BASE', TRUE, FALSE, FALSE),
('BASE+M1', TRUE, TRUE, FALSE),
('BASE+M1+M2', TRUE, TRUE, TRUE)
ON CONFLICT (name) DO NOTHING;

-- 9. Catalogue of referent statuses
CREATE TABLE IF NOT EXISTS validation_types (
    validation_type_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    validation_type_code VARCHAR(16) UNIQUE NOT NULL -- 'SKIPPED', 'VERIFICATION', 'FALSIFICATION'
);

-- Insert validation types
INSERT INTO validation_types (validation_type_code)
VALUES ('SKIPPED'), ('VERIFICATION'), ('FALSIFICATION')
ON CONFLICT (validation_type_code) DO NOTHING;

-- 10. Catalogue of validation modes
CREATE TABLE IF NOT EXISTS validation_modes (
    validation_mode_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ccl_validation_type_id INT NOT NULL REFERENCES validation_types(validation_type_id) ON DELETE CASCADE,
    stats_validation_type_id INT NOT NULL REFERENCES validation_types(validation_type_id) ON DELETE CASCADE,

	-- Creating compound indexes to speed up searching and filtering
	CONSTRAINT unique_validation_mode UNIQUE (ccl_validation_type_id, stats_validation_type_id)
);

-- Insert validation modes
INSERT INTO validation_modes (ccl_validation_type_id, stats_validation_type_id) VALUES (1, 1), (1, 2), (1, 3), (2, 1), (2, 2), (2, 3), (3, 1), (3, 2), (3, 3)
ON CONFLICT (ccl_validation_type_id, stats_validation_type_id) DO NOTHING;

-- 11. Testing modes
CREATE TABLE IF NOT EXISTS test_modes (
    test_mode_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	stats_layout_id INT NOT NULL REFERENCES stats_layouts(stats_layout_id) ON DELETE CASCADE,
	validation_mode_id INT NOT NULL REFERENCES validation_modes(validation_mode_id) ON DELETE CASCADE,

	-- Creating compound indexes to speed up searching and filtering
	CONSTRAINT unique_test_mode UNIQUE (stats_layout_id, validation_mode_id)
);

-- 12. Testing settings
CREATE TABLE IF NOT EXISTS test_settings (
    test_settings_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    test_mode_id INT NOT NULL REFERENCES test_modes(test_mode_id) ON DELETE CASCADE,
	cold_start_length INT NOT NULL DEFAULT 1 CHECK (cold_start_length > 0),
	hot_loop_length INT CHECK (hot_loop_length > 0),

	-- Creating compound indexes to speed up searching and filtering
	CONSTRAINT unique_test_settings UNIQUE (test_mode_id, cold_start_length, hot_loop_length)
);

-- 13. Benchmark list
CREATE TABLE IF NOT EXISTS benchmarks (
    benchmark_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id INT REFERENCES users(user_id) ON DELETE SET NULL,
    environment_id INT NOT NULL REFERENCES environments(environment_id) ON DELETE CASCADE,
	img_random_order BOOLEAN DEFAULT TRUE, -- order type of image processing
	iter_count INT NOT NULL DEFAULT 1 CHECK (iter_count > 0),
    start_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    end_at TIMESTAMP DEFAULT NULL,
	data_saved_at TIMESTAMP DEFAULT NULL,

	-- Creating compound indexes to speed up searching and filtering
	CONSTRAINT unique_environment_datetime UNIQUE (environment_id, start_at, end_at)
);

-- 14. Junction table for the cases when benchmark is performed on the entire dataset (1 or more)
CREATE TABLE IF NOT EXISTS benchmark_to_dataset (
	benchmark_id INT NOT NULL REFERENCES benchmarks(benchmark_id) ON DELETE CASCADE,
	dataset_id INT NOT NULL REFERENCES datasets(dataset_id) ON DELETE CASCADE,

	-- Creating compound indexes to speed up searching and filtering
	CONSTRAINT unique_benchmark_to_dataset UNIQUE (benchmark_id, dataset_id)
);

-- 15. Table showing an order of using combination of test_settings and binaries during the benchmark
CREATE TABLE IF NOT EXISTS test_treatments (
    test_treatment_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	benchmark_id INT NOT NULL REFERENCES benchmarks(benchmark_id) ON DELETE CASCADE,
	test_settings_id INT NOT NULL REFERENCES test_settings(test_settings_id) ON DELETE CASCADE,
    binary_id INT NOT NULL REFERENCES binaries(binary_id) ON DELETE CASCADE,

	-- Creating compound indexes to speed up searching and filtering
	CONSTRAINT unique_test_treatment UNIQUE (benchmark_id, test_settings_id, binary_id)
);

-- 15. Table showing an order of using test treatments during the benchmark
CREATE TABLE IF NOT EXISTS test_treatment_to_order (
	test_treatment_id INT NOT NULL UNIQUE REFERENCES test_treatments(test_treatment_id) ON DELETE CASCADE,
	treatment_order INT CHECK (treatment_order > 0)
);

-- 16. Catalogue of validity statuses
CREATE TABLE IF NOT EXISTS validation_statuses (
    validation_status_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    validation_status_code VARCHAR(16) UNIQUE NOT NULL -- 'SKIPPED', 'PASSED', 'FAILED'
);

-- Insert validation statuses
INSERT INTO validation_statuses (validation_status_code)
VALUES ('SKIPPED'), ('PASSED'), ('FAILED')
ON CONFLICT (validation_status_code) DO NOTHING;

-- 17. Main table of performance and validity measurements
CREATE TABLE IF NOT EXISTS metrics (
    -- Settings
    metric_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    image_id INT NOT NULL REFERENCES images(image_id) ON DELETE CASCADE,
	test_treatment_id INT NOT NULL REFERENCES test_treatments(test_treatment_id) ON DELETE CASCADE,
    
	-- Date, time
    measured_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
	-- Performance metrics (low-level measurements)
    cold_start_ms DOUBLE PRECISION NOT NULL,
    hot_loop_avg_ms DOUBLE PRECISION,
    hot_loop_best_ms DOUBLE PRECISION,
    -- max_throughput_mpix_sec DOUBLE PRECISION,
    -- min_cpu_cycles_per_pixel DOUBLE PRECISION,
    
	-- Validation results    
    ccl_validation_status_id INT NOT NULL REFERENCES validation_statuses(validation_status_id) ON DELETE CASCADE,
    stats_validation_status_id INT NOT NULL REFERENCES validation_statuses(validation_status_id) ON DELETE CASCADE
);

-- Creating indexes to speed up searching and filtering in dashboards
-- CREATE INDEX idx_metrics_lookup ON metrics (test_settings_id, image_id, binary_id, environment_id);

-- 1. Buffer table for FlyRLECCL's logs
CREATE TABLE IF NOT EXISTS tmp_log (
    log_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	benchmark_id INT NOT NULL REFERENCES benchmarks(benchmark_id) ON DELETE CASCADE,
    binary_id INT NOT NULL REFERENCES binaries(binary_id) ON DELETE CASCADE,
    date_time TIMESTAMP, -- = measured_at
    input_path VARCHAR(512),
    width INT,
    height INT,
    stride_bytes INT,
    mpix DOUBLE PRECISION,
	cold_start_length INT NOT NULL DEFAULT 1 CHECK (cold_start_length > 0),
	hot_loop_length INT CHECK (hot_loop_length > 0),
    stats_layout VARCHAR(32),
    cold_start_ms DOUBLE PRECISION,
    hot_loop_avg_ms DOUBLE PRECISION,
    best_time_ms DOUBLE PRECISION,
    max_perf_mpix_sec DOUBLE PRECISION,
    detected_n_components INT, -- = component_count
    foreground_area BIGINT,
    detected_n_runs INT, -- = runs_count
    ref_path VARCHAR(512),
    ref_n_components INT,
    validation VARCHAR(32) NOT NULL DEFAULT 'SKIPPED',
    ref_stats_path VARCHAR(512),
    stats_validation VARCHAR(32) NOT NULL DEFAULT 'SKIPPED',
    loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for rapid retrieval/clearing of buffers prior to ETL transformation
CREATE INDEX IF NOT EXISTS idx_fly_tmp_date ON tmp_log (date_time);

-- =========================================================================
-- 1. Analytical View for Tableau & Reporting
-- A denormalized data mart that converts milliseconds into processor cycles (CPU cycles per pixel)
-- =========================================================================
CREATE OR REPLACE VIEW v_metrics_dashboard AS
SELECT 
	-- Grouping keys
	m.image_id,
	m.test_treatment_id,

	-- Dimensions for Tableau (filters and axes)
	sl.name,
	l.lib_name,
	b.lib_version_tag,
	b.git_commit_hash,
	b.compiler_flags,
	e.env_name,
	e.cpu_model,
	e.cpu_ghz,
	e.os_info,
	ts.cold_start_length,
	ts.hot_loop_length,
	bm.img_random_order,
	bm.iter_count AS benchmark_iter_count,
	ds.name AS dataset_name,
	i.filename,
	i.width,
	i.height,
	i.width * i.height / 1000000.0 AS mpx,
	i.component_count,
	i.foreground_area,
	i.runs_count,
	i.width / i.height AS aspect_ratio,
	i.foreground_area / (i.width * i.height) AS foreground_fraction,
	i.foreground_area / i.runs_count AS mean_run_length,
	i.runs_count / i.height AS run_line_ratio,
	i.width * i.height / i.runs_count AS run_compression_ratio,
	i.foreground_area / i.component_count AS mean_component_size,
	i.runs_count / i.component_count AS runs_per_component,
	i.component_count / (i.width * i.height) AS component_density,

    -- Conversion of minimum time values ​​into processor cycles per pixel (CPU cycles per pixel)
    CASE 
        WHEN e.cpu_ghz > 0 AND (i.width * i.height) > 0 
        THEN (MIN(m.cold_start_ms) * e.cpu_ghz * 1000000.0) / (i.width * i.height)
        ELSE NULL 
    END AS min_cold_cycles_per_pixel,

    CASE 
        WHEN e.cpu_ghz > 0 AND (i.width * i.height) > 0 
        THEN (MIN(m.hot_loop_avg_ms) * e.cpu_ghz * 1000000.0) / (i.width * i.height)
        ELSE NULL 
    END AS min_hot_avg_cycles_per_pixel,

    CASE 
        WHEN e.cpu_ghz > 0 AND (i.width * i.height) > 0 
        THEN (MIN(m.hot_loop_best_ms) * e.cpu_ghz * 1000000.0) / (i.width * i.height)
        ELSE NULL 
    END AS min_hot_best_cycles_per_pixel
	
FROM metrics m
JOIN images i ON m.image_id = i.image_id
JOIN test_treatments tt ON m.test_treatment_id = tt.test_treatment_id
JOIN benchmarks bm ON tt.benchmark_id = bm.benchmark_id
LEFT JOIN users u ON bm.user_id = u.user_id
LEFT JOIN roles r ON u.role_id = r.role_id
JOIN benchmark_to_dataset bmtds ON bm.benchmark_id = bmtds.benchmark_id
JOIN datasets ds ON bmtds.dataset_id = ds.dataset_id
JOIN test_settings ts ON tt.test_settings_id = ts.test_settings_id
JOIN test_modes tm ON ts.test_mode_id = tm.test_mode_id
JOIN stats_layouts sl ON tm.stats_layout_id = sl.stats_layout_id
JOIN validation_modes vm ON tm.validation_mode_id = vm.validation_mode_id
JOIN binaries b ON tt.binary_id = b.binary_id
JOIN libs l ON b.lib_id = l.lib_id
LEFT JOIN validation_types vt_ccl ON vm.ccl_validation_type_id = vt_ccl.validation_type_id
LEFT JOIN validation_types vt_stats ON vm.stats_validation_type_id = vt_stats.validation_type_id
JOIN environments e ON bm.environment_id = e.environment_id
LEFT JOIN validation_statuses vs_ccl ON m.ccl_validation_status_id = vs_ccl.validation_status_id
LEFT JOIN validation_statuses vs_stats ON m.stats_validation_status_id = vs_stats.validation_status_id

-- Filter: keep only verification runs with a status of PASSED
WHERE l.lib_name <> 'FlyRLECCL'
	OR (vt_ccl.validation_type_code = 'VERIFICATION'
		AND vs_ccl.validation_status_code = 'PASSED'
		AND (sl.name = 'SKIPPED'
			OR (vt_stats.validation_type_code = 'VERIFICATION'
				AND vs_stats.validation_status_code = 'PASSED'
			)
		)
	)

-- Grouping to select the best (minimum) results for each treatment (unique combination of "image + binary + settings + environment" used in the corresponding benchmark)
GROUP BY
	m.image_id,
	m.test_treatment_id,
	sl.name,
	l.lib_name,
	b.lib_version_tag,
	b.git_commit_hash,
	b.compiler_flags,
	e.env_name,
	e.cpu_model,
	e.cpu_ghz,
	e.os_info,
	ts.cold_start_length,
	ts.hot_loop_length,
	bm.img_random_order,
	bm.iter_count,
	ds.name,
	i.filename,
	i.width,
	i.height,
	i.component_count,
	i.foreground_area,
	i.runs_count;

-- =======================================================================
-- Trigger for the start of a benchmark
-- =======================================================================
-- 1. Trigger-Functions
CREATE OR REPLACE FUNCTION trg_fn_benchmark_registration()
RETURNS TRIGGER AS $$
BEGIN
	NEW.end_at := NULL;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Trigger for the table benchmarks
CREATE OR REPLACE TRIGGER trg_benchmark_started
BEFORE INSERT ON benchmarks
FOR EACH ROW
EXECUTE FUNCTION trg_fn_benchmark_registration();

-- =======================================================================
-- Trigger for the end of a benchmark or for the end of copiing a log file
-- =======================================================================
-- 1. Trigger-Functions
CREATE OR REPLACE FUNCTION trg_fn_process_benchmark_etl()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.end_at IS NULL AND NEW.end_at IS NOT NULL AND NEW.end_at > OLD.start_at THEN
        -- ETL:
		-- Step 1: Create a temporary table
        CREATE TEMP TABLE tmp_data_lake ON COMMIT DROP AS
		WITH normalized_paths AS (
			-- 1: Normalization of slashes
			SELECT 
				*,
				REPLACE(input_path, E'\\', '/') AS norm_in,
				REPLACE(ref_path, E'\\', '/') AS norm_ref,
				REPLACE(ref_stats_path, E'\\', '/') AS norm_stats
			FROM tmp_log
		),
		path_parts AS (
			-- 2: Extracting directory and file names
			SELECT 
				*,
				SPLIT_PART(norm_in, '/', -2) AS in_dataset,
				SPLIT_PART(norm_in, '/', -1) AS in_filename,
				SPLIT_PART(norm_ref, '/', -2) AS ref_dataset,
				SPLIT_PART(norm_ref, '/', -1) AS ref_filename,
				SPLIT_PART(norm_stats, '/', -2) AS stats_dataset,
				SPLIT_PART(norm_stats, '/', -1) AS stats_filename
			FROM normalized_paths
		),
		tokens AS (
			-- 3: Extracting the prefix and numeric suffix for verification
			SELECT 
				*,
				REGEXP_REPLACE(in_filename, '_[^_]+_[^_]+$', '') AS in_prefix,
				-- extract number suffix
				SPLIT_PART(SPLIT_PART(ref_filename, '_', -1), '.', 1) AS ref_img_n_components
			FROM path_parts
		),
		validated_tokens AS (
			-- 4: Defining validation types
			SELECT 
				*,
				CASE 
					-- 1. If there is no reference at all
					WHEN norm_ref IS NULL OR norm_ref = '' OR norm_ref = 'N/A' THEN 'SKIPPED'
					-- 2. If the dataset name, file prefix, and number of components all match
					WHEN in_dataset = ref_dataset
						AND ref_filename LIKE '%' || in_prefix || '%'
						AND ref_img_n_components = ref_n_components::text THEN 'VERIFICATION'
					-- 3. In all other cases
					ELSE 'FALSIFICATION'
				END AS ccl_validation_type,
				CASE 
					-- 1. If there is no reference at all
					WHEN norm_stats IS NULL OR norm_stats = '' OR norm_stats = 'N/A' THEN 'SKIPPED'
					-- 2. If the dataset name, and file prefix all match
					WHEN in_dataset = stats_dataset 
						AND stats_filename LIKE '%' || in_prefix || '%' THEN 'VERIFICATION'
					-- 3. In all other cases
					ELSE 'FALSIFICATION'
				END AS stats_validation_type
			FROM tokens
		)
		SELECT
			vtokens.benchmark_id,
			vtokens.binary_id,
			vtokens.date_time, -- = measured_at
			vtokens.in_dataset AS dataset_name,
			vtokens.in_filename AS image_name,
			vtokens.width,
			vtokens.height,
			vtokens.stride_bytes,
			vtokens.cold_start_length,
			vtokens.hot_loop_length,
			sl.stats_layout_id,
			vtokens.cold_start_ms,
			vtokens.hot_loop_avg_ms,
			vtokens.best_time_ms,
			vtokens.detected_n_components, -- = component_count
			vtokens.foreground_area,
			vtokens.detected_n_runs, -- = runs_count
			vtokens.ref_n_components,
			ccl_vs.validation_status_id AS ccl_validation_status_id,
			stats_vs.validation_status_id AS stats_validation_status_id,
			vtokens.ccl_validation_type,
			vm.validation_mode_id
		FROM validated_tokens vtokens
		JOIN stats_layouts sl ON sl.name = vtokens.stats_layout
		JOIN validation_statuses ccl_vs ON
			ccl_vs.validation_status_code = vtokens.validation
		JOIN validation_statuses stats_vs ON
			stats_vs.validation_status_code = vtokens.stats_validation
		JOIN validation_types ccl_vt ON
			ccl_vt.validation_type_code = vtokens.ccl_validation_type
		JOIN validation_types stats_vt ON
			stats_vt.validation_type_code = vtokens.stats_validation_type
		JOIN validation_modes vm ON
			vm.ccl_validation_type_id = ccl_vt.validation_type_id AND
			vm.stats_validation_type_id = stats_vt.validation_type_id;
		
		-- Step 2: Registration of new test modes
		INSERT INTO test_modes (stats_layout_id, validation_mode_id)
		SELECT DISTINCT stats_layout_id, validation_mode_id
		FROM tmp_data_lake
		ON CONFLICT (stats_layout_id, validation_mode_id) DO NOTHING;
		
		-- Step 3: Registration of new test settings
		INSERT INTO test_settings (test_mode_id, cold_start_length, hot_loop_length)
		SELECT DISTINCT
			tm.test_mode_id,
			lake.cold_start_length,
			lake.hot_loop_length
		FROM tmp_data_lake lake
		JOIN test_modes tm ON tm.stats_layout_id = lake.stats_layout_id
			AND tm.validation_mode_id = lake.validation_mode_id
		ON CONFLICT (test_mode_id, cold_start_length, hot_loop_length) DO NOTHING;
		
		-- Step 4: Registration of new test treatments
		INSERT INTO test_treatments (benchmark_id, test_settings_id, binary_id)
		SELECT DISTINCT
			lake.benchmark_id,
			ts.test_settings_id,
			lake.binary_id
		FROM tmp_data_lake lake
		JOIN test_modes tm ON tm.stats_layout_id = lake.stats_layout_id AND 
			tm.validation_mode_id = lake.validation_mode_id
		JOIN test_settings ts ON ts.test_mode_id = tm.test_mode_id AND 
			ts.cold_start_length = lake.cold_start_length AND 
			ts.hot_loop_length = lake.hot_loop_length
		ON CONFLICT (benchmark_id, test_settings_id, binary_id) DO NOTHING;

		-- Step 5: Registration of new datasets
		INSERT INTO datasets (name)
		SELECT DISTINCT dataset_name
		FROM tmp_data_lake lake
		ON CONFLICT (name) DO NOTHING;
		
		-- Step 6: Registration of new images
		WITH get_ccl_params_trust_flag AS (
			SELECT 
				*,
				CASE 
					WHEN ccl_validation_type = 'VERIFICATION' AND ccl_validation_status_id = 2 THEN TRUE
					ELSE FALSE
				END AS trust_ccl_params
			FROM tmp_data_lake lake
		)
		INSERT INTO images (dataset_id, filename, width, height, stride_bytes, component_count, foreground_area, runs_count)
		SELECT DISTINCT ON (ds.dataset_id, lake.image_name)
			ds.dataset_id,
			lake.image_name,
			lake.width,
			lake.height,
			lake.stride_bytes,
			CASE
				WHEN trust_ccl_params THEN detected_n_components
				ELSE NULL
			END AS component_count,
			CASE
				WHEN trust_ccl_params THEN foreground_area
				ELSE NULL
			END AS foreground_area,
			CASE
				WHEN trust_ccl_params THEN detected_n_runs
				ELSE NULL
			END AS runs_count
		FROM get_ccl_params_trust_flag lake
		JOIN datasets ds ON ds.name = lake.dataset_name
		ORDER BY ds.dataset_id, lake.image_name, trust_ccl_params DESC
		ON CONFLICT (dataset_id, filename)
		DO UPDATE SET
			component_count = COALESCE(images.component_count, EXCLUDED.component_count),
			foreground_area = COALESCE(images.foreground_area, EXCLUDED.foreground_area),
			runs_count = COALESCE(images.runs_count, EXCLUDED.runs_count)
		-- Update the row ONLY if at least one of the fields has actually changed.
		WHERE
			images.component_count IS DISTINCT FROM COALESCE(images.component_count, EXCLUDED.component_count) OR  
			images.foreground_area IS DISTINCT FROM COALESCE(images.foreground_area, EXCLUDED.foreground_area) OR 
			images.runs_count IS DISTINCT FROM COALESCE(images.runs_count, EXCLUDED.runs_count);
	
		-- Step 7: Registration of mitrics
		INSERT INTO metrics (
			image_id,
			test_treatment_id,
			measured_at,
			cold_start_ms,
			hot_loop_avg_ms,
			hot_loop_best_ms,
			ccl_validation_status_id,
			stats_validation_status_id
		)
		SELECT
			i.image_id,
			tt.test_treatment_id,
			lake.date_time,
			lake.cold_start_ms,
			lake.hot_loop_avg_ms,
			lake.best_time_ms,
			lake.ccl_validation_status_id,
			lake.stats_validation_status_id
		FROM tmp_data_lake lake
		JOIN test_modes tm ON tm.stats_layout_id = lake.stats_layout_id AND 
			tm.validation_mode_id = lake.validation_mode_id
		JOIN test_settings ts ON ts.test_mode_id = tm.test_mode_id AND 
			ts.cold_start_length = lake.cold_start_length AND 
			ts.hot_loop_length = lake.hot_loop_length
		JOIN test_treatments tt ON tt.benchmark_id = lake.benchmark_id AND
			tt.test_settings_id = ts.test_settings_id AND
			tt.binary_id = lake.binary_id
		JOIN datasets d ON d.name = lake.dataset_name
		JOIN images i ON i.dataset_id = d.dataset_id AND
			i.filename = lake.image_name;
		
		-- Step 8: tmp_data_lake cleaning
        DELETE FROM tmp_log WHERE benchmark_id = NEW.benchmark_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Trigger on the table benchmarks
CREATE OR REPLACE TRIGGER trg_benchmark_finished
BEFORE UPDATE OF end_at ON benchmarks
FOR EACH ROW
EXECUTE FUNCTION trg_fn_process_benchmark_etl();