{% test amount_less_than_zero( model, column_name, group_by_column, col_id = '') %}
    {% if col_id == '' %}
select 
    {{ group_by_column }},
    sum( {{ column_name }} ) as amount
from {{ model }}
group by 1
having not(amount >= 0)
{% else %}
select 
    {{ group_by_column }},
    sum( {{ column_name }} ) as amount
from {{ model }}
group by 1
having not(amount >= 1)
{% endif %}
{% endtest %}
