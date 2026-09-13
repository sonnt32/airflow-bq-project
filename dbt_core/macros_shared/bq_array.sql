{#
  bq_array(lst) -> chuỗi literal BigQuery ARRAY từ 1 list Python/Jinja.
  Dùng để bơm var (--vars '{"versions": ["1.0.8","1.0.9"]}') vào UNNEST(...) trong SQL.
  Ví dụ: {{ bq_array(['1.0.8','1.0.9']) }}  ->  ['1.0.8', '1.0.9']
         {{ bq_array([]) }}                  ->  []
#}
{% macro bq_array(lst) -%}
[{%- for v in lst -%}'{{ v }}'{%- if not loop.last -%}, {%- endif -%}{%- endfor -%}]
{%- endmacro %}
