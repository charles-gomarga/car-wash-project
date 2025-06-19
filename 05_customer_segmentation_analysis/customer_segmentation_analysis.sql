--Query 1: Total Customer per Plan

--Purpose: Calculate the number of active customers under each subscription plan and their proportion relative to the total active customer population.
--SQL features: Common Table Expression (CTE), COUNT(DISTINCT), INNER JOIN, ROUND(), and Window Function (SUM() OVER()).

WITH total_cust_per_plan AS(
	SELECT
		plan_name,
		COUNT(DISTINCT customer_id) AS total_customer --Count unique active customers per plan.
	FROM subscription s
	JOIN plan p ON s.plan_id = p.plan_id
	WHERE is_active=1 --Consider only active subscriptions
	GROUP BY p.plan_id, plan_name
)

SELECT
	plan_name,
	total_customer,
	ROUND(total_customer/SUM(total_customer) OVER()*100, 2) || '%' AS ratio -- Calculate the percentage ratio of customers on each plan.
FROM total_cust_per_plan

/*=========================================================================================================================================================*/

--Query 2: Visit Frequency Segmentation

--Purpose: Segment customers by visit frequency relative to the maximum allowed visits based on their subscription plan.
--Logic:
	--Low: less than 25% of max allowed visits
	--Medium: between 25%–50%
	--High: more than 50%
--Note:
	--Segments visits at the vehicle level.
	--Plan visit caps are normalized (Diamond = 30 visits/month).
	--Only active subscriptions are considered.

--SQL features: Common Table Expression (CTE), CASE WHEN, COUNT(), and GROUP BY.

-- Normalize visit limits (Diamond plan = 30 visits)
WITH normalized_max_visit AS(
	SELECT
		plan_id,
		CASE WHEN plan_id=4 THEN 30 ELSE max_visit_per_month END AS max_visit
	FROM plan
),
-- Count total visits per active vehicle and join with customer info
visit_counter AS(
	SELECT
		s.customer_id AS customer_id,
		first_name || ' ' || last_name AS full_name,
		s.vehicle_id AS vehicle_id,
		COUNT(visit_id)::FLOAT AS total_visit,
		max_visit
	FROM subscription s
	JOIN normalized_max_visit nmv ON nmv.plan_id=s.plan_id
	JOIN visit v ON s.subscription_id=v.subscription_id
	JOIN customer c ON c.customer_id=s.customer_id
	WHERE is_active=1
	GROUP BY s.customer_id, full_name, s.vehicle_id, max_visit
)
-- Segment into Low, Medium, or High frequency
SELECT
	customer_id,
	full_name,
	vehicle_id,
	CASE
		WHEN total_visit/max_visit < 0.25 THEN 'Low'
		WHEN total_visit/max_visit > 0.5 THEN 'High'
		ELSE 'Medium'
	END AS visit_frequency
FROM visit_counter

/*=========================================================================================================================================================*/

--Query 3: Total Visit for Multi-vehicle Customers.

--Purpose: Track how frequently each vehicle is used by customers who own more than one vehicle, focusing only on visits within the past 30 days.
--SQL features: Common Table Expression (CTE), COUNT(), GROUP BY, INNER JOIN, HAVING, and INTERVAL

-- Identify customers who own more than one vehicle
WITH multi_vehicle AS(
	SELECT customer_id FROM vehicle
	GROUP BY customer_id
	HAVING COUNT(vehicle_id)>1
)
-- Count total visits per vehicle (last 30 days) for multi-vehicle customers
SELECT
	mv.customer_id,
	v.vehicle_id,
	COUNT(visit_id) AS total_visit
FROM multi_vehicle mv
JOIN vehicle v ON mv.customer_id=v.customer_id
JOIN visit vi ON v.vehicle_id=vi.vehicle_id
WHERE visit_date >= CURRENT_DATE - INTERVAL '30 days' -- Only include recent visits
GROUP BY mv.customer_id, v.vehicle_id
ORDER BY mv.customer_id

/*=========================================================================================================================================================*/

--Query 4: Behavioral Drift Detection

--Purpose: Detects sudden behavioral changes in customer engagement based on their visit activity compared to the previous month.
--Classification Rules:
	--Safe: Activity stayed the same or increased.
	--Low Churn Risk: Visit drop less than 50%.
	--High Churn Risk: Visit drop of 50% or more.

--SQL features: Common Table Expression (CTE), DATE_TRUNC(), COALESCE(), CASE WHEN, ROUND(), and COUNT(DISTINCT)

--Identify currently active customers
WITH active_customer AS(
	SELECT
		customer_id
	FROM subscription
	WHERE is_active=1
),
--Count total visits per month per vehicle for each active customer
visit_data AS(
	SELECT
		ac.customer_id AS customer_id,
		v.vehicle_id AS vehicle_id,
		DATE_TRUNC('Month', visit_date) AS visit_month,
		COUNT(DISTINCT visit_id) AS total_visit
	FROM active_customer ac
	JOIN vehicle v ON ac.customer_id=v.customer_id
	JOIN visit vi ON v.vehicle_id=vi.vehicle_id
	WHERE visit_date>=DATE_TRUNC('Month', CURRENT_DATE) - INTERVAL '1 Months'
	GROUP BY ac.customer_id, v.vehicle_id, visit_month
),
--Compare total visits for current vs previous month
visit_comparison AS(
	SELECT
		customer_id,
		vehicle_id,
		COALESCE(MAX(CASE WHEN visit_month = DATE_TRUNC('Month', CURRENT_DATE) - INTERVAL '1 Months' THEN total_visit END),0) AS previous_month,
		COALESCE(MAX(CASE WHEN visit_month = DATE_TRUNC('Month', CURRENT_DATE) THEN total_visit END),0) AS current_month
	FROM visit_data
	GROUP BY customer_id, vehicle_id
),
--Calculate behavior drift ratio
drift_detection AS(
	SELECT
		*,
		CASE
			WHEN previous_month=0 THEN current_month
			ELSE ROUND(((current_month-previous_month)::FLOAT/previous_month)::NUMERIC,2)
		END AS drift_ratio
	FROM visit_comparison
)
--Classify the drift level
SELECT
	customer_id,
	vehicle_id,
	CASE
		WHEN drift_ratio >= 0 THEN 'Safe'
		WHEN drift_ratio <= -0.5 THEN 'High Churn Risk'
		ELSE 'Low Churn Risk'
	END AS customer_status
FROM drift_detection

/*=========================================================================================================================================================*/

--Query 5: Downgrade Behavior

--Purpose: Detects customers who downgraded their subscription plan within the past 6 months.
--Notes:
	--Higher plan_id = higher plan tier (e.g., Diamond = 4, Gold = 2, etc.)
	--Only vehicle-level downgrades are tracked.

-- Prepare customer subscription history with next plan and month using window functions
WITH plan_data AS(
	SELECT
		customer_id,
		vehicle_id,
		DATE_TRUNC('Month', start_date) AS start_month_raw,
		plan_id,
		--Look ahead to the next subscription for the same customer and vehicle
		LEAD(DATE_TRUNC('Month', start_date)) OVER(PARTITION BY customer_id, vehicle_id ORDER BY DATE_TRUNC('Month', start_date)) AS next_month_raw,
		
		LEAD(plan_id) OVER (PARTITION BY customer_id, vehicle_id ORDER BY DATE_TRUNC('Month', start_date)) AS next_plan_id
	FROM subscription
)
--Extract downgrade behavior
SELECT
	first_name || ' ' || last_name AS full_name,
	vehicle_id,
	TO_CHAR(start_month_raw, 'FMMonth yyyy') AS start_month,
	CASE WHEN p1.plan_id=pd.plan_id THEN p1.plan_name END AS plan_name,
	TO_CHAR(next_month_raw, 'FMMonth yyyy') AS next_month,
	CASE WHEN p2.plan_id=pd.next_plan_id THEN p2.plan_name END AS next_plan_name,
	pd.next_plan_id - pd.plan_id || ' tiers' AS downgrade
FROM plan_data pd
JOIN customer c ON c.customer_id=pd.customer_id
JOIN plan p1 ON p1.plan_id=pd.plan_id
JOIN plan p2 ON p2.plan_id=pd.next_plan_id
WHERE pd.next_plan_id IS NOT NULL
	AND pd.next_plan_id < pd.plan_id -- Downgrade detected
	AND start_month_raw >= DATE_TRUNC('Month', CURRENT_DATE) - INTERVAL '6 Months'