DROP VIEW public.raincell_grid;
CREATE OR REPLACE VIEW public.raincell_grid
    AS
     SELECT raincell_core_cell.id,
    st_setsrid(st_envelope(st_buffer(raincell_core_cell.location, (0.025 / 2::numeric)::double precision)), 4326) AS geom
   FROM raincell_core_cell;


CREATE OR REPLACE VIEW public.rain_last_day AS
WITH aggregated_records AS (
         SELECT raincell_core_atomicrainrecord.cell_id,
            array_agg((raincell_core_atomicrainrecord.recorded_time || '/'::text) || raincell_core_atomicrainrecord.quantile50) AS data
           FROM raincell_core_atomicrainrecord
          WHERE raincell_core_atomicrainrecord.recorded_time >= (now()::timestamp without time zone - '1 day'::interval) AND raincell_core_atomicrainrecord.recorded_time <= now()::timestamp without time zone
          GROUP BY raincell_core_atomicrainrecord.cell_id
        ), rain_cells_aggregated_records AS (
         SELECT r.cell_id,
            r.data,
            g.id,
            g.geom
           FROM aggregated_records r
             RIGHT JOIN raincell_grid g ON r.cell_id::text = g.id::text
        )
 SELECT rain_cells_aggregated_records.cell_id,
    rain_cells_aggregated_records.data,
    rain_cells_aggregated_records.id,
    rain_cells_aggregated_records.geom
   FROM rain_cells_aggregated_records;

-- DROP FUNCTION postgisftw.rain_at_time;
-- CREATE OR REPLACE FUNCTION postgisftw.rain_at_time(
--                         ref_time text default '2022-06-14T23:55:00+00:00',
--                         duration text default '2 days')
-- RETURNS TABLE(cell_id VARCHAR, rc_data JSON, id VARCHAR, geom geometry)
-- AS $$
-- BEGIN
-- 	RETURN QUERY
-- 		WITH
-- 		aggregated_records AS (
-- 			SELECT r.cell_id, json_agg(json_build_object('time', r.recorded_time, 'q50', r.quantile50)) AS rc_data
-- 			FROM raincell_core_atomicrainrecord AS r
--           	WHERE r.recorded_time BETWEEN ref_time::timestamp  - duration::interval AND ref_time::timestamp
-- 			GROUP BY r.cell_id
-- 		)
--
-- 		SELECT r.*, g.*
-- 		FROM aggregated_records AS r RIGHT JOIN raincell_grid AS g
-- 			ON r.cell_id=g.id;
-- END;
-- $$
-- LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;
--
-- COMMENT ON FUNCTION postgisftw.rain_on_day IS 'Returns the rain on the given datetime, with a history period defined by duration parameter (defaults 2 days)';



CREATE OR REPLACE FUNCTION postgisftw.rain_at_time_and_cell(
                        cell_ident text default NULL,
                        ref_time text default '2022-06-14T23:55:00+00:00',
                        duration text default '2 days')
RETURNS TABLE(cell_id VARCHAR, rc_data JSON, id VARCHAR, geom geometry)
AS $$
BEGIN
	RETURN QUERY
		WITH
		aggregated_records AS (
			SELECT r.cell_id, json_agg(json_build_object('time', r.recorded_time, 'q50', r.quantile50)) AS rc_data
			FROM raincell_core_atomicrainrecord AS r
          	WHERE r.recorded_time BETWEEN ref_time::timestamp  - duration::interval AND ref_time::timestamp
			GROUP BY r.cell_id
		)

		SELECT r.*, g.*
		FROM aggregated_records AS r INNER JOIN raincell_grid AS g
			ON r.cell_id=g.id
			WHERE cell_ident IS NULL OR r.cell_id = cell_ident;
END;
$$
LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;

COMMENT ON FUNCTION postgisftw.rain_on_day IS 'Returns the rain on the given datetime, with a history period defined by duration parameter (defaults 2 days)';


-- DROP FUNCTION postgisftw.rain_at_time;
CREATE OR REPLACE FUNCTION postgisftw.rain_at_time4(
                        ref_time text default '2022-06-14T23:55:00+00:00',
                        duration text default '2 days')
RETURNS TABLE(cell_id VARCHAR, rc_data JSON, id VARCHAR, geom geometry)
AS $$
BEGIN
	RETURN QUERY
		SELECT postgisftw.rain_at_time_and_cell(NULL, ref_time, duration);
END;
$$
LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;



-- DROP VIEW public.raincell_daily_records;
CREATE OR REPLACE VIEW public.raincell_daily_records
    AS
SELECT cell_id, recorded_time::date AS recorded_date, ROUND(AVG(quantile50)::NUMERIC, 2) AS avg
FROM raincell_core_atomicrainrecord
GROUP BY cell_id, recorded_time::date
ORDER BY cell_id,recorded_date;

-- Provides the daily values service (& full dataset too, as a bonus)
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
			SELECT r.cell_id, json_agg(json_build_object('date', r.recorded_date, 'value', r.avg)) AS rc_data
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

COMMENT ON FUNCTION postgisftw.rain_daily_at_date_and_cell IS 'Returns the daily rain (mean over the day) on the given datetime, with a history period defined by duration parameter (defaults 2 days)';







--
--
--
-- Try to reduce the size of the downloaded data
--
--



-- Provides the 15m values service (& full geographic dataset too, as a bonus if you let cell_ident to NULL)
CREATE OR REPLACE FUNCTION postgisftw.rain_at_time_and_cell(
                        cell_ident text default NULL,
                        ref_time text default '2022-06-14T23:55:00+00:00',
                        duration text default '1 days')
RETURNS TABLE(cell_id VARCHAR, rc_data JSON, id VARCHAR, geom geometry)
AS $$
BEGIN
	RETURN QUERY
		WITH
		aggregated_records AS (
			SELECT r.cell_id, json_agg(json_build_object('d', to_char(r.recorded_time, 'YYYYMMDD'),'t', to_char(r.recorded_time, 'HH24MI'), 'v', r.quantile50)) AS rc_data
			FROM raincell_core_atomicrainrecord AS r
          	WHERE r.recorded_time BETWEEN ref_time::timestamp  - duration::interval AND ref_time::timestamp
			GROUP BY r.cell_id
		)

		SELECT r.*, g.*
		FROM aggregated_records AS r INNER JOIN raincell_grid AS g
			ON r.cell_id=g.id
			WHERE cell_ident IS NULL OR r.cell_id = cell_ident;
END;
$$
LANGUAGE 'plpgsql' STABLE PARALLEL SAFE;

COMMENT ON FUNCTION postgisftw.rain_at_time_and_cell IS 'Returns the rain on the given datetime, with a history period defined by duration parameter (defaults 2 days). Results limited to the cell_ident value, unless set to NULL (default) in which case it will return the full geospatial dataset (all cells). ref_time is expected as a full datetime character strin (e.g. "2022-06-14T23:55:00+00:00". But be aware that you might have, in case of passing this parameter from a browser URL, to escape it: in that case, replace the "+" by "%2B")';






-- Provides the 15m values service (& full geographic dataset too, as a bonus if you let cell_ident to NULL)
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
  			SELECT r.cell_id, to_char(r.recorded_time, 'YYYYMMDD') AS d, json_agg(json_build_object('t', to_char(r.recorded_time, 'HH24MI'), 'v', r.quantile50)) AS rc_data
  			FROM raincell_core_atomicrainrecord AS r
            	WHERE r.recorded_time BETWEEN '2022-06-14T13:55:00+00:00'::timestamp  - '1 day'::interval AND '2022-06-14T13:55:00+00:00'::timestamp
  			GROUP BY r.cell_id, to_char(r.recorded_time, 'YYYYMMDD')
	   ),
		aggregated_records AS (
			SELECT r.cell_id, json_agg(json_build_object('d', r.d, 'rc_data', r.rc_data))
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

COMMENT ON FUNCTION postgisftw.rain_at_time_and_cell IS 'Returns the rain on the given datetime, with a history period defined by duration parameter (defaults 2 days). Results limited to the cell_ident value, unless set to NULL (default) in which case it will return the full geospatial dataset (all cells). ref_time is expected as a full datetime character strin (e.g. "2022-06-14T23:55:00+00:00". But be aware that you might have, in case of passing this parameter from a browser URL, to escape it: in that case, replace the "+" by "%2B")';


-- Provides the 15m values service (& full geographic dataset too, as a bonus if you let cell_ident to NULL)
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
  			SELECT r.cell_id, to_char(r.recorded_time, 'YYYYMMDD') AS d, json_agg(json_build_object(to_char(r.recorded_time, 'HH24MI'), r.quantile50)) AS v
  			FROM raincell_core_atomicrainrecord AS r
            	WHERE r.recorded_time BETWEEN '2022-06-14T13:55:00+00:00'::timestamp  - '1 day'::interval AND '2022-06-14T13:55:00+00:00'::timestamp
  			GROUP BY r.cell_id, to_char(r.recorded_time, 'YYYYMMDD')
	   ),
		aggregated_records AS (
			SELECT r.cell_id, json_agg(json_build_object('d', r.d, 'rc_data', r.rc_data))
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

COMMENT ON FUNCTION postgisftw.rain_at_time_and_cell IS 'Returns the rain on the given datetime, with a history period defined by duration parameter (defaults 2 days). Results limited to the cell_ident value, unless set to NULL (default) in which case it will return the full geospatial dataset (all cells). ref_time is expected as a full datetime character strin (e.g. "2022-06-14T23:55:00+00:00". But be aware that you might have, in case of passing this parameter from a browser URL, to escape it: in that case, replace the "+" by "%2B")';


-- CREATE OR REPLACE FUNCTION public.atomicrain_cells_for_date(
-- 	z integer,
-- 	x integer,
-- 	y integer,
-- 	ref_date date DEFAULT '2022-06-14'::date,
-- 	duration text DEFAULT '2 days'::text)
--     RETURNS bytea
--     LANGUAGE 'plpgsql'
--
--     COST 100
--     STABLE PARALLEL SAFE
--
-- AS $BODY$
-- DECLARE
--                 result bytea;
--             BEGIN
-- 			IF z > 4 then
--                 WITH
--                 bounds AS (
--                   SELECT ST_TileEnvelope(z, x, y) AS geom
--                 ),
-- 				aggregated_records AS (
--
-- select cell_id, array_agg(recorded_time || '/' || quantile50 ) AS data
-- FROM raincell_core_atomicrainrecord
-- WHERE recorded_time BETWEEN '2022-06-14'::timestamp  - '1 day'::interval AND '2022-06-14'::timestamp
-- GROUP BY cell_id
-- 				),
--                 rain_cells_aggregated_records AS (
-- 					SELECT r.*, g.*
-- 					FROM aggregated_records AS r RIGHT JOIN raincell_grid AS g
-- 						ON r.cell_id=g.id
--                 ),
--                 mvtgeom AS (
--                   SELECT t.id, ST_AsMVTGeom(ST_Transform(t.geom, 3857), bounds.geom) AS geom,
--                     t.data
--                   FROM rain_cells_aggregated_records t, bounds
--                   WHERE ST_Intersects(t.geom, ST_Transform(bounds.geom, 4326))
--                 )
--                 SELECT ST_AsMVT(mvtgeom, 'default')
--                 INTO result
--                 FROM mvtgeom;
--
--                 RETURN result;
-- 			END IF;
-- 			RETURN NULL;
--             END;
-- $BODY$;
