-- =============================================================================
-- FILE: 04_ani_benchmark.sql
-- PURPOSE: Benchmark procedure - run in SQL Workshop to get timing data
-- NOTE: Calls ani_api package functions directly. No review data needed.
-- =============================================================================

-- Create log table if not exists
BEGIN
    EXECUTE IMMEDIATE '
        CREATE TABLE ani_benchmark_log (
            log_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            run_at       TIMESTAMP DEFAULT SYSTIMESTAMP,
            method       VARCHAR2(10),
            row_limit    NUMBER,
            run_number   NUMBER,
            elapsed_ms   NUMBER,
            result_bytes NUMBER
        )';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -955 THEN NULL;
        ELSE RAISE;
        END IF;
END;
/


CREATE OR REPLACE PROCEDURE ani_run_benchmark (
    p_runs   IN NUMBER DEFAULT 5,
    p_limits IN SYS.ODCINUMBERLIST DEFAULT SYS.ODCINUMBERLIST(100, 500)
)
AS
    v_start      TIMESTAMP;
    v_end        TIMESTAMP;
    v_elapsed_ms NUMBER;
    v_result     CLOB;
    v_bytes      NUMBER;

    TYPE t_summary IS RECORD (
        total_ms NUMBER,
        min_ms   NUMBER,
        max_ms   NUMBER,
        runs     NUMBER
    );
    TYPE t_summary_tab IS TABLE OF t_summary INDEX BY VARCHAR2(30);
    v_summary t_summary_tab;

    FUNCTION lkey(p_method VARCHAR2, p_limit NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN p_method || '_' || p_limit;
    END lkey;

BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== ANI_ Benchmark (' || p_runs || ' runs per method/limit) ===');
    DBMS_OUTPUT.PUT_LINE(RPAD('Method',8) || RPAD('Limit',8) || RPAD('Run',6) || RPAD('ms',10) || 'Bytes');
    DBMS_OUTPUT.PUT_LINE(RPAD('-',55,'-'));

    FOR i IN 1 .. p_limits.COUNT LOOP
        DECLARE
            v_limit NUMBER := p_limits(i);
        BEGIN
            -- Warm-up run (not recorded)
            v_result := ani_api.get_anime_sql(v_limit);
            v_result := ani_api.get_anime_loop(v_limit);

            FOR run IN 1 .. p_runs LOOP

                -- SQL method
                v_start      := SYSTIMESTAMP;
                v_result     := ani_api.get_anime_sql(v_limit);
                v_end        := SYSTIMESTAMP;
                v_elapsed_ms := (EXTRACT(MINUTE FROM (v_end - v_start)) * 60
                              +  EXTRACT(SECOND FROM (v_end - v_start))) * 1000;
                v_bytes      := DBMS_LOB.GETLENGTH(v_result);

                INSERT INTO ani_benchmark_log (method, row_limit, run_number, elapsed_ms, result_bytes)
                VALUES ('sql', v_limit, run, ROUND(v_elapsed_ms, 2), v_bytes);

                IF NOT v_summary.EXISTS(lkey('sql', v_limit)) THEN
                    v_summary(lkey('sql', v_limit)).total_ms := 0;
                    v_summary(lkey('sql', v_limit)).min_ms   := 999999;
                    v_summary(lkey('sql', v_limit)).max_ms   := 0;
                    v_summary(lkey('sql', v_limit)).runs     := 0;
                END IF;
                v_summary(lkey('sql', v_limit)).total_ms := v_summary(lkey('sql', v_limit)).total_ms + v_elapsed_ms;
                v_summary(lkey('sql', v_limit)).min_ms   := LEAST(v_summary(lkey('sql', v_limit)).min_ms, v_elapsed_ms);
                v_summary(lkey('sql', v_limit)).max_ms   := GREATEST(v_summary(lkey('sql', v_limit)).max_ms, v_elapsed_ms);
                v_summary(lkey('sql', v_limit)).runs     := v_summary(lkey('sql', v_limit)).runs + 1;

                DBMS_OUTPUT.PUT_LINE(RPAD('SQL', 8) || RPAD(v_limit, 8) || RPAD(run, 6)
                    || RPAD(ROUND(v_elapsed_ms, 1), 10) || v_bytes);

                -- LOOP method
                v_start      := SYSTIMESTAMP;
                v_result     := ani_api.get_anime_loop(v_limit);
                v_end        := SYSTIMESTAMP;
                v_elapsed_ms := (EXTRACT(MINUTE FROM (v_end - v_start)) * 60
                              +  EXTRACT(SECOND FROM (v_end - v_start))) * 1000;
                v_bytes      := DBMS_LOB.GETLENGTH(v_result);

                INSERT INTO ani_benchmark_log (method, row_limit, run_number, elapsed_ms, result_bytes)
                VALUES ('loop', v_limit, run, ROUND(v_elapsed_ms, 2), v_bytes);

                IF NOT v_summary.EXISTS(lkey('loop', v_limit)) THEN
                    v_summary(lkey('loop', v_limit)).total_ms := 0;
                    v_summary(lkey('loop', v_limit)).min_ms   := 999999;
                    v_summary(lkey('loop', v_limit)).max_ms   := 0;
                    v_summary(lkey('loop', v_limit)).runs     := 0;
                END IF;
                v_summary(lkey('loop', v_limit)).total_ms := v_summary(lkey('loop', v_limit)).total_ms + v_elapsed_ms;
                v_summary(lkey('loop', v_limit)).min_ms   := LEAST(v_summary(lkey('loop', v_limit)).min_ms, v_elapsed_ms);
                v_summary(lkey('loop', v_limit)).max_ms   := GREATEST(v_summary(lkey('loop', v_limit)).max_ms, v_elapsed_ms);
                v_summary(lkey('loop', v_limit)).runs     := v_summary(lkey('loop', v_limit)).runs + 1;

                DBMS_OUTPUT.PUT_LINE(RPAD('LOOP', 8) || RPAD(v_limit, 8) || RPAD(run, 6)
                    || RPAD(ROUND(v_elapsed_ms, 1), 10) || v_bytes);

            END LOOP;

            DBMS_OUTPUT.PUT_LINE('');
        END;
    END LOOP;

    COMMIT;

    -- Summary
    DBMS_OUTPUT.PUT_LINE('=== SUMMARY ===');
    DBMS_OUTPUT.PUT_LINE(RPAD('Method',8) || RPAD('Limit',8) || RPAD('Avg ms',10)
        || RPAD('Min ms',10) || RPAD('Max ms',10) || 'Speedup');
    DBMS_OUTPUT.PUT_LINE(RPAD('-',55,'-'));

    FOR i IN 1 .. p_limits.COUNT LOOP
        DECLARE
            v_limit    NUMBER := p_limits(i);
            v_sql_avg  NUMBER;
            v_loop_avg NUMBER;
        BEGIN
            v_sql_avg  := v_summary(lkey('sql',  v_limit)).total_ms / v_summary(lkey('sql',  v_limit)).runs;
            v_loop_avg := v_summary(lkey('loop', v_limit)).total_ms / v_summary(lkey('loop', v_limit)).runs;

            DBMS_OUTPUT.PUT_LINE(
                RPAD('SQL',  8) || RPAD(v_limit, 8)
                || RPAD(ROUND(v_sql_avg, 1), 10)
                || RPAD(ROUND(v_summary(lkey('sql', v_limit)).min_ms, 1), 10)
                || RPAD(ROUND(v_summary(lkey('sql', v_limit)).max_ms, 1), 10)
                || '—'
            );
            DBMS_OUTPUT.PUT_LINE(
                RPAD('LOOP', 8) || RPAD(v_limit, 8)
                || RPAD(ROUND(v_loop_avg, 1), 10)
                || RPAD(ROUND(v_summary(lkey('loop', v_limit)).min_ms, 1), 10)
                || RPAD(ROUND(v_summary(lkey('loop', v_limit)).max_ms, 1), 10)
                || ROUND(v_loop_avg / NULLIF(v_sql_avg, 0), 1) || 'x slower'
            );
            DBMS_OUTPUT.PUT_LINE('');
        END;
    END LOOP;

END ani_run_benchmark;
/


-- =============================================================================
-- RUN THE BENCHMARK
-- =============================================================================
BEGIN
    ani_run_benchmark(
        p_runs   => 5,
        p_limits => SYS.ODCINUMBERLIST(100, 500)
    );
END;
/


-- =============================================================================
-- QUERY RESULTS
-- =============================================================================
SELECT
    method,
    row_limit,
    COUNT(*)                    AS runs,
    ROUND(AVG(elapsed_ms), 1)  AS avg_ms,
    ROUND(MIN(elapsed_ms), 1)  AS min_ms,
    ROUND(MAX(elapsed_ms), 1)  AS max_ms
FROM ani_benchmark_log
GROUP BY method, row_limit
ORDER BY row_limit, method;
