-- Bronze: vendor file as delivered (after structural repair), every column varchar.
select * from {{ ref('raw_catalog') }}
