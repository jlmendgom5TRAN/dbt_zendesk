with calendar_spine as (
    select *
    from {{ ref('int_zendesk__calendar_spine') }} 


), ticket_metrics as (
    select *
    from {{ ref('zendesk__ticket_metrics') }}

), user_table as (
    select *
    from {{ ref('stg_zendesk__user') }}

), user_sum as (
    select 
        {{ dbt_utils.date_trunc("day", "created_at") }} as created_at,
        sum(case when is_active = true
            then 1
            else 0
                end) as user_count,
        sum(case when lower(role) != 'end-user' and is_active = true
            then 1
            else 0
                end) as active_agent_count,
        sum(case when is_active = false
            then 1
            else 0
                end) as deleted_user_count,
        sum(case when lower(role) = 'end-user' and is_active = true
            then 1
            else 0
                end) as end_user_count,
        sum(case when is_suspended = true
            then 1
            else 0
                end) as suspended_user_count
    from user_table

    group by 1

), ticket_metric_sum_created as (
    select 
        {{ dbt_utils.date_trunc("day", "created_at") }} as created_at,
        sum(case when lower(status) = 'new'
            then 1
            else 0
                end) as new_ticket_count,
        sum(case when lower(status) = 'hold'
            then 1
            else 0
                end) as on_hold_ticket_count,
        sum(case when lower(status) = 'open'
            then 1
            else 0
                end) as open_ticket_count,
        sum(case when lower(status) = 'pending'
            then 1
            else 0
                end) as pending_ticket_count,
        sum(case when lower(type) = 'problem'
            then 1
            else 0
                end) as problem_ticket_count,
        sum(case when first_assignee_id != last_assignee_id
            then 1
            else 0
                end) as reassigned_ticket_count,
        sum(case when count_reopens > 0
            then 1
            else 0
                end) as reopened_ticket_count,

        --If you use using_satisfaction_ratings this will be included, if not it will be ignored.
        {% if var('using_satisfaction_ratings', True) %}
        sum(case when lower(ticket_satisfaction_rating) in ('offered', 'good', 'bad')
            then 1
            else 0
                end) as surveyed_satisfaction_ticket_count,
        {% endif %}

        sum(case when assignee_id is null and lower(status) not in ('solved', 'closed')
            then 1
            else 0
                end) as unassigned_unsolved_ticket_count,
        sum(case when total_agent_replies < 0
            then 1
            else 0
                end) as unreplied_ticket_count,
        sum(case when total_agent_replies < 0 and lower(status) not in ('solved', 'closed')
            then 1
            else 0
                end) as unreplied_unsolved_ticket_count,
        sum(case when lower(status) not in ('solved', 'closed')
            then 1
            else 0
                end) as unsolved_ticket_count,
        count(count_internal_comments) as total_internal_comments,
        count(count_public_comments) as total_public_comments,
        count(total_comments)
    from ticket_metrics

    group by 1

), ticket_metric_sum_solved as (
    select 
        coalesce({{ dbt_utils.date_trunc("day", "last_solved_at") }}, {{ dbt_utils.date_trunc("day", "updated_at") }}) as created_at,
        sum(case when lower(status) in ('solved', 'closed')
            then 1
            else 0
                end) as solved_ticket_count
    from ticket_metrics

    group by 1

), final as (
    select
        calendar_spine.date_day,
        user_sum.user_count,
        user_sum.active_agent_count,
        user_sum.deleted_user_count,
        user_sum.end_user_count,
        user_sum.suspended_user_count,
        ticket_metric_sum_created.new_ticket_count,
        ticket_metric_sum_created.on_hold_ticket_count,
        ticket_metric_sum_created.open_ticket_count,
        ticket_metric_sum_created.pending_ticket_count,
        ticket_metric_sum_solved.solved_ticket_count,
        ticket_metric_sum_created.problem_ticket_count,
        ticket_metric_sum_created.reassigned_ticket_count,
        ticket_metric_sum_created.reopened_ticket_count,

        --If you use using_satisfaction_ratings this will be included, if not it will be ignored.
        {% if var('using_satisfaction_ratings', True) %}
        ticket_metric_sum_created.surveyed_satisfaction_ticket_count,
        {% endif %}

        ticket_metric_sum_created.unassigned_unsolved_ticket_count,
        ticket_metric_sum_created.unreplied_ticket_count,
        ticket_metric_sum_created.unreplied_unsolved_ticket_count,
        ticket_metric_sum_created.unsolved_ticket_count
    from calendar_spine

    left join user_sum
        on user_sum.created_at = cast(calendar_spine.date_day as {{ dbt_utils.type_timestamp() }})

    left join ticket_metric_sum_created
        on ticket_metric_sum_created.created_at = cast(calendar_spine.date_day as {{ dbt_utils.type_timestamp() }})

    left join ticket_metric_sum_solved
        on ticket_metric_sum_solved.created_at = cast(calendar_spine.date_day as {{ dbt_utils.type_timestamp() }})
)

select *
from final