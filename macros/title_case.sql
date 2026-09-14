{#- Title Case a string: trim, collapse repeated spaces, capitalise each word. NULL stays NULL. -#}
{% macro title_case(expr) -%}
array_to_string(
    list_transform(
        list_filter(string_split(lower(trim({{ expr }})), ' '), lambda w: w <> ''),
        lambda w: upper(left(w, 1)) || substr(w, 2)
    ),
    ' '
)
{%- endmacro %}
