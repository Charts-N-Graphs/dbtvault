{#- Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
-#}
{%- macro eff_sat(src_pk, src_dfk, src_sfk, src_start_date, src_end_date, src_eff, src_ldts, src_source, link_model, source_model) -%}

    {{- adapter_macro('dbtvault.eff_sat', src_pk=src_pk, src_dfk=src_dfk, src_sfk=src_sfk,
                      src_start_date=src_start_date, src_end_date=src_end_date,
                      src_eff=src_eff, src_ldts=src_ldts, src_source=src_source,
                      link_model=link_model, source_model=source_model) -}}

{%- endmacro %}

{%- macro default__eff_sat(src_pk, src_dfk, src_sfk, src_start_date, src_end_date, src_eff, src_ldts, src_source, link_model, source_model) -%}

{%- set source_cols = dbtvault.expand_column_list(columns=[src_pk, src_dfk, src_sfk, src_start_date, src_end_date, src_eff, src_ldts, src_source]) -%}

{%- set structure_cols = dbtvault.expand_column_list(columns=[src_pk, src_start_date, src_end_date, src_eff, src_ldts, src_source]) -%}

-- Generated by dbtvault.
-- depends_on: {{ ref(link_model) }}

WITH source_data AS (

    SELECT *
    FROM {{ ref(source_model) }}
    {% if dbtvault.is_vault_insert_by_period() or model.config.materialized == 'vault_insert_by_period' %}
        WHERE __PERIOD_FILTER__
        AND {{ src_dfk }} IS NOT NULL
        AND {{ src_sfk }} IS NOT NULL
    {% else %}
        WHERE {{ src_dfk }} IS NOT NULL
        AND {{ src_sfk }} IS NOT NULL
    {% endif %}
)

{% if load_relation(this) is none -%}
    SELECT {{ dbtvault.alias_all(structure_cols, 'e') }}
    FROM source_data AS e
{% else %}
    ,latest_open_eff AS
    (
        SELECT {{ dbtvault.alias_all(structure_cols, 'a') }}
        FROM (
                SELECT {{ dbtvault.alias_all(structure_cols, 'b') }},
                ROW_NUMBER() OVER (PARTITION BY b.{{ src_pk }} ORDER BY b.{{ src_ldts }} DESC) AS RowNum
                FROM {{ this }} AS b
        ) AS a
        WHERE TO_DATE(a.{{ src_end_date }}) = TO_DATE('9999-12-31')
        AND a.RowNum = 1
    ),
    stage_slice AS
    (
        SELECT {{ dbtvault.alias_all(source_cols, 'stg') }}
        FROM source_data AS stg
    ),
    open_links AS (
        SELECT c.*
        FROM {{ ref(link_model) }} AS c
        INNER JOIN latest_open_eff AS d
        ON c.{{ src_pk }} = d.{{ src_pk }}
    ),
    links_to_end_date AS (
      SELECT a.{{ src_pk }}, a.{{ src_dfk }}
      FROM open_links AS a
      LEFT JOIN stage_slice AS stg
      ON a.{{ src_dfk }} = stg.{{ src_dfk }}
      WHERE stg.{{ src_sfk }} IS NULL
      OR stg.{{ src_sfk }} <> a.{{ src_sfk }}
    )
    SELECT DISTINCT
        {{ dbtvault.alias_all(structure_cols, 'slice_a') }}
    FROM stage_slice AS slice_a
    LEFT JOIN
        latest_open_eff AS e
        ON slice_a.{{ src_pk }} = e.{{ src_pk }}
        WHERE e.{{ src_pk }} IS NULL
    UNION
    SELECT DISTINCT
        h.{{ src_pk }}, h.{{ src_start_date }}, slice_b.EFFECTIVE_FROM AS {{ src_end_date }},
        slice_b.{{ src_eff}}, slice_b.{{ src_ldts }}, h.{{ src_source }}
    FROM LATEST_OPEN_EFF AS h
    INNER JOIN
        LINKS_TO_END_DATE AS g
        ON g.{{ src_pk }} = h.{{ src_pk }}
        INNER JOIN
        stage_slice AS slice_b
        ON g.{{ src_dfk }} = slice_b.{{ src_dfk }}
{% endif %}
{% endmacro %}