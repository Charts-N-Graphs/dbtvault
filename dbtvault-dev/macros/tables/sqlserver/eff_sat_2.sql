{%- macro sqlserver__eff_sat_2(src_pk, src_dfk, src_sfk, src_status, src_hashdiff, src_eff, src_ldts, src_source, source_model) -%}

{{- dbtvault.check_required_parameters(src_pk=src_pk, src_dfk=src_dfk, src_sfk=src_sfk,
                                       src_status=src_status, src_hashdiff=src_hashdiff, src_eff=src_eff, src_ldts=src_ldts,
                                       src_source=src_source, source_model=source_model) -}}

{%- set src_pk = dbtvault.escape_column_names(src_pk) -%}
{%- set src_dfk = dbtvault.escape_column_names(src_dfk) -%}
{%- set src_sfk = dbtvault.escape_column_names(src_sfk) -%}
{%- set src_status = dbtvault.escape_column_names(src_status) -%}
{%- set src_hashdiff = dbtvault.escape_column_names(src_hashdiff) -%}
{%- set src_eff = dbtvault.escape_column_names(src_eff) -%}
{%- set src_ldts = dbtvault.escape_column_names(src_ldts) -%}
{%- set src_source = dbtvault.escape_column_names(src_source) -%}

{%- set source_cols = dbtvault.expand_column_list(columns=[src_pk, src_dfk, src_sfk, src_status, src_hashdiff, src_eff, src_ldts, src_source]) -%}
{%- set fk_cols = dbtvault.expand_column_list(columns=[src_dfk, src_sfk]) -%}
{%- set dfk_cols = dbtvault.expand_column_list(columns=[src_dfk]) -%}
{%- set is_auto_end_dating = config.get('is_auto_end_dating', default=false) %}
{%- set HASHDIFF_F = dbtvault.hash(columns='!0', alias=src_hashdiff, is_hashdiff=false) -%}

{{- dbtvault.prepend_generated_by() }}

WITH source_data AS (
    SELECT {{ dbtvault.prefix(source_cols, 'a', alias_target='source') }}
    FROM {{ ref(source_model) }} AS a
    WHERE {{ dbtvault.multikey(src_dfk, prefix='a', condition='IS NOT NULL') }}
    AND {{ dbtvault.multikey(src_sfk, prefix='a', condition='IS NOT NULL') }}
    {%- if model.config.materialized == 'vault_insert_by_period' %}
    AND __PERIOD_FILTER__
    {%- elif model.config.materialized == 'vault_insert_by_rank' %}
    AND __RANK_FILTER__
    {%- endif %}
),

{%- if dbtvault.is_any_incremental() %}

{# Selecting the most recent records for each link hashkey -#}
latest_records AS (
    SELECT *
    FROM (
        SELECT {{ dbtvault.alias_all(source_cols, 'b') }},
        ROW_NUMBER() OVER (
        PARTITION BY {{ dbtvault.prefix([src_pk], 'b') }}
        ORDER BY b.{{ src_ldts }} DESC
        ) AS row_num
        FROM {{ this }} AS b
    ) AS x
    WHERE row_num = 1
),

{# Selecting the open records of the most recent records for each link hashkey -#}
latest_open AS (
    SELECT {{ dbtvault.alias_all(source_cols, 'c') }}
    FROM latest_records AS c
    WHERE c.{{ src_status }} = CAST('TRUE' AS BIT)
),

{# Selecting the closed records of the most recent records for each link hashkey -#}
latest_closed AS (
    SELECT {{ dbtvault.alias_all(source_cols, 'd') }}
    FROM latest_records AS d
    WHERE d.{{ src_status }} = CAST('FALSE' AS BIT)
),

{# Identifying the completely new link relationships to be opened in eff sat -#}
new_open_records AS (
    SELECT DISTINCT
        {{ dbtvault.alias_all(source_cols, 'f') }}
    FROM source_data AS f
    LEFT JOIN latest_records AS lr
    ON {{ dbtvault.multikey(src_pk, prefix=['f','lr'], condition='=') }}
    WHERE {{ dbtvault.multikey(src_pk, prefix='lr', condition='IS NULL') }}
),

{# Identifying the currently closed link relationships to be reopened in eff sat -#}
new_reopened_records AS (
    SELECT DISTINCT
        {{ dbtvault.prefix([src_pk], 'lc') }},
        {{ dbtvault.alias_all(fk_cols, 'lc') }},
        g.{{ src_status }},
        g.{{ src_hashdiff }},
        g.{{ src_eff }},
        g.{{ src_ldts }},
        g.{{ src_source }}
    FROM source_data AS g
    INNER JOIN latest_closed AS lc
    ON {{ dbtvault.multikey(src_pk, prefix=['g','lc'], condition='=') }}
    WHERE g.{{ src_status }} = CAST('TRUE' AS BIT)
),

{%- if is_auto_end_dating %}

{# Creating the closing records -#}
{# Identifying the currently open relationships that need to be closed due to change in SFK(s) -#}
new_closed_records AS (
    SELECT DISTINCT
        {{ dbtvault.prefix([src_pk], 'lo') }},
        {{ dbtvault.alias_all(fk_cols, 'lo') }},
        CAST('FALSE' AS BIT) AS {{ src_status }},
        {{ HASHDIFF_F }},
        h.{{ src_eff }},
        h.{{ src_ldts }},
        lo.{{ src_source }}
    FROM source_data AS h
    INNER JOIN latest_open AS lo
    ON {{ dbtvault.multikey(src_dfk, prefix=['lo', 'h'], condition='=') }}
    WHERE ({{ dbtvault.multikey(src_sfk, prefix=['lo', 'h'], condition='<>', operator='OR') }})
),

{#- else if is_auto_end_dating -#}
{% else %}

new_closed_records AS (
    SELECT DISTINCT
        {{ dbtvault.prefix([src_pk], 'lo') }},
        {{ dbtvault.alias_all(fk_cols, 'lo') }},
        h.{{ src_status }},
        h.{{ src_hashdiff }},
        h.{{ src_eff }},
        h.{{ src_ldts }},
        lo.{{ src_source }}
    FROM source_data AS h
    LEFT JOIN Latest_open AS lo
    ON {{ dbtvault.multikey(src_pk, prefix=['lo', 'h'], condition='=') }}
    LEFT JOIN latest_closed AS lc
    ON {{ dbtvault.multikey(src_pk, prefix=['lc', 'h'], condition='=') }}
    WHERE h.{{ src_status }} = CAST('FALSE' AS BIT)
    AND {{ dbtvault.multikey(src_pk, prefix='lo', condition='IS NOT NULL') }}
    AND {{ dbtvault.multikey(src_pk, prefix='lc', condition='IS NULL') }}
),

{#- end if is_auto_end_dating -#}
{%- endif %}

records_to_insert AS (
    SELECT * FROM new_open_records
    UNION
    SELECT * FROM new_reopened_records
    UNION
    SELECT * FROM new_closed_records
)

{#- else if not dbtvault.is_any_incremental() -#}
{%- else %}

records_to_insert AS (
    SELECT {{ dbtvault.alias_all(source_cols, 'i') }}
    FROM source_data AS i
)

{#- end if not dbtvault.is_any_incremental() -#}
{%- endif %}

SELECT *
FROM records_to_insert

{%- endmacro -%}

