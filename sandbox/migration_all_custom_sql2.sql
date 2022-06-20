--
-- Util views
--
-- DROP VIEW public.raincell_grid CASCADE;
CREATE OR REPLACE VIEW public.raincell_grid
    AS
     SELECT raincell_core_cell.id,
       st_envelope(st_buffer(raincell_core_cell.location, (0.025 / 2::numeric)::double precision))::geometry(Geometry, 4326) AS geom
   FROM raincell_core_cell;


-- DROP VIEW public.raincell_daily_records;
CREATE OR REPLACE VIEW public.raincell_daily_records
    AS
SELECT cell_id, recorded_time::date AS recorded_date, ROUND(AVG(quantile50)::NUMERIC, 2) AS avg
FROM raincell_core_atomicrainrecord
GROUP BY cell_id, recorded_time::date
ORDER BY cell_id,recorded_date;



--
-- pg_featureserv views and functions
--

-- Provides the 15m values service (& full geographic dataset too, as a bonus if you let cell_ident to NULL)
-- Optimized version compared to above: from 6,7MB to 2.3MB for full dataset (1 day)
CREATE OR REPLACE FUNCTION postgisftw.rain_at_time_and_cell(
                        cell_ident text default NULL,
                        ref_time text default '2022-06-14T23:55:00+00:00',
                        duration text default '1 days')
RETURNS TABLE(cell_id VARCHAR, rc_data JSON, id VARCHAR, geom geometry)
AS $$
BEGIN
	RETURN QUERY
		WITH
    agg1 AS (
  			SELECT r.cell_id, to_char(r.recorded_time, 'YYYYMMDD') AS d, json_agg(json_build_object(
                      't', to_char(r.recorded_time, 'HH24MI'),
                      'q25',r.quantile25,
                      'q50',r.quantile50,
                      'q75',r.quantile75
                    )
                    ORDER BY r.recorded_time) AS v
  			FROM raincell_core_atomicrainrecord AS r
            	WHERE r.recorded_time BETWEEN ref_time::timestamp  - duration::interval AND ref_time::timestamp
  			GROUP BY r.cell_id, to_char(r.recorded_time, 'YYYYMMDD')
	   ),
		aggregated_records AS (
			SELECT r.cell_id, json_agg(json_build_object('d', r.d, 'v', r.v) ORDER BY r.d) AS rc_data
    	FROM agg1 AS r
    	GROUP BY r.cell_id
		)

		SELECT r.*, g.*
		FROM aggregated_records AS r INNER JOIN raincell_grid AS g
			ON r.cell_id=g.id
			WHERE cell_ident IS NULL OR r.cell_id = cell_ident;
END;
$$
LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;


COMMENT ON FUNCTION postgisftw.rain_at_time_and_cell IS 'Returns the rain on the given datetime, with a history period defined by duration parameter (defaults 2 days). Results limited to the cell_ident value, unless set to NULL (default) in which case it will return the full geospatial dataset (all cells), which represent several MB. ref_time is expected as a full datetime character string (e.g. "2022-06-14T23:55:00+00:00". But be aware that you might have, in case of passing this parameter from a browser URL, to escape it: in that case, replace the "+" by "%2B")';


-- DROP FUNCTION postgisftw.rain_at_time;
CREATE OR REPLACE FUNCTION postgisftw.rain_at_time(
                        ref_time text default '2022-06-14T23:55:00+00:00',
                        duration text default '2 days')
RETURNS TABLE(cell_id VARCHAR, rc_data JSON, id VARCHAR, geom geometry)
AS $$
BEGIN
	RETURN QUERY
		SELECT * FROM postgisftw.rain_at_time_and_cell(NULL, ref_time, duration);
END;
$$
LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;
COMMENT ON FUNCTION postgisftw.rain_at_time IS 'Returns the rain on the given datetime, with a history period defined by duration parameter (defaults 2 days). Is just a special case of rain_at_time_and_cell, where cell_ident is not a variable anymore (set to NULL => all the dataset is returned)';




-- Provides the daily values service (& full geographic dataset too, as a bonus if you let cell_ident to NULL)
CREATE OR REPLACE FUNCTION postgisftw.rain_daily_at_date_and_cell(
                        cell_ident text default NULL,
                        ref_date date default '2022-06-14',
                        duration text default '50 days')
RETURNS TABLE(cell_id VARCHAR, rc_data JSON, id VARCHAR, geom geometry)
AS $$
BEGIN
	RETURN QUERY
		WITH
		aggregated_records AS (
			SELECT r.cell_id, json_agg(json_build_object('d', r.recorded_date, 'v', r.avg)) AS rc_data
			FROM raincell_daily_records AS r
          	WHERE r.recorded_date BETWEEN ref_date::date  - duration::interval AND ref_date::date
			GROUP BY r.cell_id
		)

		SELECT r.*, g.*
		FROM aggregated_records AS r INNER JOIN raincell_grid AS g
			ON r.cell_id=g.id
			WHERE cell_ident IS NULL OR r.cell_id = cell_ident;
END;
$$
LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;

COMMENT ON FUNCTION postgisftw.rain_daily_at_date_and_cell IS 'Returns the daily rain (mean over the day) on the given day, with a history period defined by duration parameter (defaults "50 days"). Results limited to the cell_ident value, unless set to NULL (default) in which case it will return the full geospatial dataset (all cells), which represent several MB. Beware that the duration needs to be a postgresq interval, as defined in https://www.postgresql.org/docs/14/datatype-datetime.html. E.g. "50 days", which is very different from "50" (no unit)';

--
--
-- Creating and managing subsampled data (lower resolution grids)
--

-- subsampled grid generation function
-- TODO maybe move it to a procedure, and create views from there
CREATE OR REPLACE FUNCTION public.raincell_grid_subsample(
	cell_size float default 0.5
)
RETURNS TABLE(id VARCHAR, geom geometry)
    AS
	$$
BEGIN
	RETURN QUERY
		WITH ext AS (
				SELECT ST_SetSRID(ST_Extent(raincell_grid.geom),4326) AS geom FROM raincell_grid
			),
			grid_sub AS (
				SELECT (ST_SquareGrid(cell_size, ST_Transform(ext.geom,4326))).*
				FROM ext
			)
		SELECT DISTINCT ('g'||cell_size::text||'_'||a.i||'_'||a.j)::varchar AS id, a.geom::geometry(Geometry, 4326) FROM grid_sub a, raincell_core_cell b WHERE ST_Contains(a.geom,b.location);
END;
$$
LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;


--
-- Procedure, that automatically builds
--  - the subsampled geo grids (no data). Names of kind raincell_grid_sub{cell_size_string}
--  - the atomic data on those subsampled geo grid (no time-based aggregate). Names of kind raincell_atomicrainrecord_sub{cell_size_string}
-- where cell_size_string is made out of cell_size var, but removing the ".".
--
CREATE OR REPLACE PROCEDURE public.raincell_grid_make_subsample_views()
    AS
	$$
DECLARE
   cell_size  float;
BEGIN
	FOREACH cell_size IN ARRAY ARRAY[0.05, 0.1, 0.2, 0.4, 0.8] LOOP
		EXECUTE format('CREATE OR REPLACE VIEW  %I  AS SELECT * FROM public.raincell_grid_subsample(%L)', 'raincell_grid_sub' || replace(cell_size::text, '.',''), cell_size);
		--EXECUTE format('DROP VIEW %I', 'raincell_atomicrainrecord_sub' || replace(cell_size::text, '.',''));
		EXECUTE format('
			-- create subsampled data as views
			CREATE OR REPLACE VIEW %I AS
			WITH geo_records AS (
				SELECT t.*, g.location
				FROM raincell_core_atomicrainrecord t, raincell_core_cell g
				WHERE t.cell_id = g.id
			)
			SELECT g.id AS cell_id, r.recorded_time, round(avg(r.quantile25)::numeric,2) AS quantile25, round(avg(r.quantile50)::numeric,2) AS quantile50, round(avg(r.quantile75)::numeric, 2) AS quantile75, g.geom
			FROM geo_records r, %I g
			WHERE ST_contains(g.geom, r.location)
			GROUP BY r.recorded_time, g.id, g.geom;',
    'raincell_atomicrainrecord_sub' || replace(cell_size::text, '.',''),
    'raincell_grid_sub' || replace(cell_size::text, '.','')
    );

	END LOOP;
END
$$
LANGUAGE 'plpgsql';

-- execute the procedure
CALL public.raincell_grid_make_subsample_views();

-- Create a view exposing the original data, but spatialized to match the subsampled views structure
CREATE OR REPLACE VIEW public.raincell_atomicrainrecord_geo AS
SELECT r.*, g.geom
FROM raincell_core_atomicrainrecord r INNER JOIN raincell_grid g
ON r.cell_id = g.id;


--
-- MVT functions
--
-- fetches data from subsample datasets based on zoom level
-- DROP FUNCTION mvt_rain_cells_for_time;
CREATE OR REPLACE
FUNCTION mvt_rain_cells_for_time(
            z integer, x integer, y integer,
            ref_time text default '2022-06-14T23:55:00+00:00',
            duration text default '1 day')
RETURNS bytea
AS $$
DECLARE
    tblname text;
    result bytea;
BEGIN
    CASE
        WHEN z < 3 THEN
            tblname := 'raincell_atomicrainrecord_sub08';
        WHEN z < 5 THEN
            tblname := 'raincell_atomicrainrecord_sub04';
        WHEN z < 6 THEN
            tblname := 'raincell_atomicrainrecord_sub02';
        WHEN z < 7 THEN
            tblname := 'raincell_atomicrainrecord_sub01';
        WHEN z < 8 THEN
            tblname := 'raincell_atomicrainrecord_sub005';
        ELSE
            tblname := 'raincell_atomicrainrecord_geo';
    END CASE;
  EXECUTE format('
    WITH
    bounds AS (
      SELECT ST_TileEnvelope($3, $1, $2) AS geom
    ),
    agg1 AS (
            SELECT r.cell_id, to_char(r.recorded_time, ''YYYYMMDD'') AS d, json_agg(json_build_object(''t'', to_char(r.recorded_time, ''HH24MI''), ''v'', r.quantile50)) AS rc_data, r.geom
            FROM %I AS r
            WHERE r.recorded_time BETWEEN $4::timestamp  - $5::interval AND $4::timestamp
            GROUP BY cell_id, to_char(r.recorded_time, ''YYYYMMDD''), r.geom
    ),
    agg_geo AS (
        SELECT r.cell_id, json_agg(json_build_object(''d'', r.d, ''rc_data'', r.rc_data)) AS rc_data, r.geom
        FROM agg1 AS r
        GROUP BY r.cell_id, r.geom
    ),
    mvtgeom AS (
      SELECT t.cell_id, ST_AsMVTGeom(ST_Transform(t.geom, 3857), bounds.geom) AS geom,
        t.rc_data
      FROM agg_geo t, bounds
      WHERE ST_Intersects(t.geom, ST_Transform(bounds.geom, 4326))
    )
    SELECT ST_AsMVT(mvtgeom, ''mvt_rain_cells_for_time'')

    FROM mvtgeom;
    ', tblname)
    USING x, y, z, ref_time, duration
    INTO result;

    RETURN result;
END;
$$
LANGUAGE 'plpgsql'
STABLE
PARALLEL SAFE;

COMMENT ON FUNCTION mvt_rain_cells_for_time IS 'Returns MVT. Aggregates data for the given datetime, with a history period defined by duration parameter (defaults 1 day).  Depending on the zoom level, the data will be aggregated into larger cells, to avoid sending huge VT. ref_time is expected as a full datetime character string (e.g. "2022-06-14T23:55:00+00:00". But be aware that you might have, in case of passing this parameter from a browser URL, to escape it: in that case, replace the "+" by "%2B"';
