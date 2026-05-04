-- =============================================================================
-- FILE: 03_ani_ords_handlers.sql
-- PURPOSE: Register the ORDS module and GET handler for the anime benchmark.
--          The handler calls ani_api package functions directly and streams
--          the CLOB response in chunks using HTP.PRN.
--
-- COMPATIBILITY: Oracle 19c+ | ORDS 21+
-- RUN AFTER: ani_api_pkg.sql (package must exist first)
--
-- ENDPOINT: GET /ani/anime/list
-- PARAMETERS:
--   method  = sql  (default) | loop
--   lim     = number of rows to return (default 100)
--
-- EXAMPLE:
--   /ords/consultantforge/ani/anime/list?method=sql&lim=500
--   /ords/consultantforge/ani/anime/list?method=loop&lim=500
-- =============================================================================

BEGIN
    -- Remove module if it already exists
    BEGIN
        ORDS.DELETE_MODULE(p_module_name => 'ani.benchmark');
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END;

    -- Create module
    ORDS.DEFINE_MODULE(
        p_module_name    => 'ani.benchmark',
        p_base_path      => '/ani/',
        p_items_per_page => 0,
        p_status         => 'PUBLISHED',
        p_comments       => 'Anime JSON benchmark - SQL vs PL/SQL loop'
    );

    -- Create template
    ORDS.DEFINE_TEMPLATE(
        p_module_name => 'ani.benchmark',
        p_pattern     => 'anime/list'
    );

    -- Create GET handler
    -- The handler:
    --   1. Reads :method and :lim bind variables (passed as URL parameters)
    --   2. Calls the appropriate ani_api function
    --   3. Streams the CLOB result in 32KB chunks using HTP.PRN
    --      (HTP.P cannot handle large CLOBs and throws ORA-06502)
    ORDS.DEFINE_HANDLER(
        p_module_name    => 'ani.benchmark',
        p_pattern        => 'anime/list',
        p_method         => 'GET',
        p_source_type    => ORDS.source_type_plsql,
        p_items_per_page => 0,
        p_source         => q'[
DECLARE
    l_result CLOB;
    l_limit  NUMBER       := 100;
    l_method VARCHAR2(10) := 'sql';
    l_offset PLS_INTEGER  := 1;
    l_chunk  VARCHAR2(32767);
    l_length PLS_INTEGER;
BEGIN
    l_method := NVL(:method, 'sql');
    l_limit  := NVL(:lim, 100);

    IF l_method = 'loop' THEN
        l_result := ani_api.get_anime_loop(l_limit);
    ELSE
        l_result := ani_api.get_anime_sql(l_limit);
    END IF;

    :status_code  := 200;
    :content_type := 'application/json';

    -- Stream CLOB in 32KB chunks.
    -- HTP.PRN does not add a newline, keeping JSON intact across boundaries.
    -- Do not use HTP.P for CLOBs — it only handles VARCHAR2 and throws ORA-06502.
    l_length := DBMS_LOB.GETLENGTH(l_result);
    WHILE l_offset <= l_length LOOP
        l_chunk  := DBMS_LOB.SUBSTR(l_result, 32767, l_offset);
        HTP.PRN(l_chunk);
        l_offset := l_offset + 32767;
    END LOOP;

EXCEPTION
    WHEN OTHERS THEN
        :status_code := 500;
        HTP.P('{"error":"' || REPLACE(SQLERRM, '"', '''') || '"}');
END;]'
    );

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('ORDS module ani.benchmark registered successfully.');
    DBMS_OUTPUT.PUT_LINE('Endpoint: /ani/anime/list?method=sql&lim=100');
END;
/
