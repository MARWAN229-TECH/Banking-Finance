SET @reference_date = '2025-01-10';

with savings_revenue as (
select
c.customer_id,
round(sum(current_balance*(interest_rate/100)),2) as saving_interest_revenue
from customers c inner join accounts a on c.customer_id=a.customer_id
where account_type = 'Savings'
group by c.customer_id),

credit_card_revenue as (
select
customer_id,
round(sum( ABS(current_balance)*(interest_rate/100)),2) as credit_revenue
from accounts
where account_type='Credit Card'
group by customer_id),


loan_revenue as(
select
customer_id,
round(sum(loan_amount*(interest_rate/100)),2) as loan_revenue
from loans
where status='active'
group by customer_id),

total_revenue as (
select 
c.customer_id,
concat(c.first_name,' ',c.last_name) as full_name,
coalesce(cc.credit_revenue,0) as credit_revenue,
coalesce(s.saving_interest_revenue,0) as saving_interest_revenue,
coalesce(l.loan_revenue,0) as loan_revenue,

(coalesce(l.loan_revenue,0)+
coalesce(cc.credit_revenue,0)+
coalesce(s.saving_interest_revenue,0)) as total_revenue

from customers c  
 left join savings_revenue s on c.customer_id = s.customer_id 
 left join credit_card_revenue cc on c.customer_id=cc.customer_id
left join loan_revenue l on c.customer_id=l.customer_id
),

customer_segments as (
select
*,
case 
WHEN total_revenue >= 5000 THEN 'High Value'
            WHEN total_revenue >= 1000 THEN 'Medium Value'
            WHEN total_revenue > 0 THEN 'Low Value'
            ELSE 'Unprofitable' end as profitability_tier
            from total_revenue)
            select*from customer_segments
            order by total_revenue desc;



with customer_last_transaction as(
select 
 a.customer_id,
 concat(c.first_name,' ',c.last_name) as full_name,
 max(t.transaction_date) as last_transaction_date,
 datediff(@reference_date ,max(t.transaction_date)) as days_since_last_transaction,
 count(t.transaction_id) as total_transactions
 from customers c  left join accounts a on c.customer_id=a.customer_id
 left join transactions t on a.account_id=t.account_id
 group by  a.customer_id,full_name),

recency_activity as (
select
 c.customer_id,
 count(
 case when  t.transaction_date>=date_sub(@reference_date ,interval 30 DAY) then 1 end) as transactions_last_30_days,
 count(
 case when t.transaction_date>=date_sub(@reference_date ,interval 90 DAY) then 1 end) as transactions_last_90_days
   FROM customers c
    LEFT JOIN accounts a ON c.customer_id = a.customer_id
    LEFT JOIN transactions t ON a.account_id = t.account_id
    GROUP BY c.customer_id),
 

activity_segment as (
 select
 clt.*,
 ra.transactions_last_30_days,
 ra.transactions_last_90_days,
 CASE 
            WHEN clt.last_transaction_date IS NULL THEN 'Never Transacted'
            WHEN clt.days_since_last_transaction <= 30 THEN 'Active'
            WHEN clt.days_since_last_transaction <= 90 THEN 'At Risk'
            WHEN clt.days_since_last_transaction <= 180 THEN 'Dormant'
            ELSE 'Churned'
 end as activity_status
 from customer_last_transaction clt left join recency_activity ra on
 clt.customer_id = ra.customer_id)
 select
 activity_status,
 count(*) as customer_count,
   ROUND(AVG(total_transactions), 1) AS avg_lifetime_transactions,
    ROUND(AVG(days_since_last_transaction), 0) AS avg_days_inactive,
     ROUND(AVG(transactions_last_30_days), 1) as avg_transactions_last_30d
     from activity_segment
     group by activity_status
     order by 
      case activity_status WHEN 'Active' THEN 1
        WHEN 'At Risk' THEN 2
        WHEN 'Dormant' THEN 3
        WHEN 'Churned' THEN 4
        WHEN 'Never Transacted' THEN 5
    END;
    
    with customer_loans as (
    select
    l.loan_id,
    l.loan_amount*(l.interest_rate/100) as total_interest,
    l.interest_rate,
    l.loan_amount,
    l.monthly_payment,
	l.status as loan_status,
    l.loan_type,
    c.credit_score,
    c.risk_category   , 
	c.customer_id,
	concat(c.first_name,' ',c.last_name) as customer_name
    from loans l
    inner join customers c on l.customer_id=c.customer_id),
    
    loan_risk_scoring as (
   select*,
   case 
    when loan_status='Default' then 'Defaulted'
    when loan_status='Active' and credit_score<600 and risk_category='High' then 'High Risk'
   when loan_status='Active' and credit_score<650 then 'High Risk'
   when loan_status='Active' and (credit_score<750 or interest_rate > 12) then 'Medium Risk'
   when loan_status='Paid Off' then 'Success'
   else 'Low Risk'
    end as risk_tier
    from customer_loans)
   select
   risk_tier,
   loan_type,
   count(*) as loan_count,
   round(sum(loan_amount),0) as total_exposure,
    ROUND(AVG(credit_score), 0) AS avg_credit_score,
    ROUND(AVG(interest_rate), 2) AS avg_interest_rate
   from loan_risk_scoring
   group by risk_tier,loan_type
   order by 
    case risk_tier
    when 'Defaulted' then 1
    when 'High Risk' then 2 
    when 'Medium Risk' then 3 
	when 'Low Risk' then 4
    when 'Paid Off' then 5
   end,
   total_exposure desc;
   