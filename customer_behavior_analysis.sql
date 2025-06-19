--Query 1: Active vs Inactive Customers

--Purpose: Compare the number of active versus inactive customers based on their most recent subscription.
--Notes: Each customer may own multiple vehicles. The analysis considers only the most recent subscription per vehicle.

--SQL features: Common Table Expression (CTE), RANK() window function, CASE WHEN, COUNT(DISTINCT), JOIN, and ORDER BY.

WITH recent_subs AS (
	SELECT	
		c.customer_id AS customer_id,
		is_active,
		end_date,
		RANK() OVER(PARTITION BY c.customer_id, s.vehicle_id ORDER BY end_date DESC) AS date_rank --1st rank is the most recent subscription.
	FROM customer c
	JOIN subscription s ON c.customer_id=s.customer_id
)

SELECT
	CASE
		WHEN is_active=0 THEN 'Inactive'
		ELSE 'Active'
	END AS subscription_status,
	--COUNT(*) AS total_vehicles	--To count per vehicle.
	COUNT(DISTINCT customer_id) AS total_customers --To count per customer.
FROM recent_subs
WHERE date_rank=1
GROUP BY subscription_status
ORDER BY total_customers ASC; --or total_vehicles.

/*===========================================================================================================================================================*/

--Query 2: New Customers

--Purpose: Count the total number of new customers whose first subscription started in the current month.
--Notes: 
	--This query assumes a static reference date (May 2025) for analysis.
	--Replace DATE '2025-05-01' with CURRENT_DATE for dynamic use in real-time environments.
	--Can be adapted to count per vehicle instead of per customer by changing the GROUP BY.
	
--SQL features: Common Table Expression (CTE), MIN(), DATE_TRUNC(), COUNT(), and INNER JOIN.

WITH first_subs AS(
SELECT
	customer_id, --Count total new subscriptions per customer
	--vehicle_id,  --Count total new subscriptions per vehicle
	MIN(start_date) AS first_start
FROM subscription
GROUP BY customer_id --or use vehicle_id for per-vehicle analysis
)

SELECT
	COUNT(*) AS total_new_subs
FROM first_subs s
WHERE DATE_TRUNC('MONTH', first_start)=DATE_TRUNC('MONTH', DATE '2025-05-01'); --Replace with CURRENT_DATE for dynamic filtering.

/*===========================================================================================================================================================*/

--Query 3: Active Customers with No Visits.

--Purpose: Identify active customers who either haven't visited in the last 30 days or have never visited at all.
--Notes: 
	--The visit threshold can be adjusted by changing the interval ('30 days').
	--Displays key customer information including contact and vehicle details.
	--Uses LEFT JOIN to ensure customers with no visit history are included.

--SQL features: CONCAT(), MAX(), INNER JOIN, LEFT JOIN, INTERVAL, GROUP BY, HAVING, ORDER BY.

SELECT
	c.customer_id,
	CONCAT(first_name, ' ', last_name) AS full_name,
	email AS customer_email,
	phone_number AS customer_phone,
	license_plate AS vehicle_plate,
	MAX(visit_date) AS last_visit_date
FROM customer c
JOIN vehicle v ON c.customer_id=v.customer_id
JOIN subscription s ON v.vehicle_id=s.vehicle_id AND is_active=1
LEFT JOIN visit vi ON v.vehicle_id=vi.vehicle_id
GROUP BY c.customer_id, license_plate
HAVING MAX(visit_date) IS NULL OR MAX(visit_date) < CURRENT_DATE - INTERVAL '30 days'
ORDER BY last_visit_date DESC NULLS LAST;

/*===========================================================================================================================================================*/

--Query 4: Multi-vehicle Customers

--Purpose: Identify customers who own more than one vehicle and display the total number of subscriptions they’ve made.
--Notes: 
	--Customers with more than one vehicle are filtered using a HAVING COUNT(vehicle_id) > 1 clause.
	--Subscription count may reflect repeated renewals per vehicle.

--SQL features: Common Table Expression (CTE), INNER JOIN, GROUP BY, HAVING, COUNT().

WITH multi_vehicle AS(
	SELECT
		c.customer_id
	FROM customer c
	JOIN vehicle v ON c.customer_id=v.customer_id
	GROUP BY c.customer_id
	HAVING COUNT(vehicle_id)>1
)

SELECT
	mv.customer_id,
	COUNT(subscription_id) AS total_subscriptions
FROM multi_vehicle mv
JOIN subscription s ON mv.customer_id=s.customer_id
GROUP BY mv.customer_id
ORDER BY mv.customer_id ASC;

/*===========================================================================================================================================================*/

--Query 5: Churn Potential Customers

--Purpose: Identify active customers who haven’t visited in the past 60 days and whose subscription is ending within the next 14 days — strong indicators of potential churn.
--Notes:
	--active_cust CTE filters for currently active subscriptions.
	--churn_risk filters customers who haven’t visited recently and are near the subscription end.
	--The result includes customer ID, vehicle ID, subscription ID, end date, and last visit.

--SQL features: Common Table Expression (CTE), MAX(), BETWEEN, INTERVAL, HAVING, JOIN and GROUP BY

WITH active_cust AS(
	SELECT 
		customer_id, vehicle_id, subscription_id, end_date
	FROM subscription
	WHERE is_active=1
),
churn_risk AS(
	SELECT
		customer_id,
		ac.vehicle_id,
		ac.subscription_id,
		end_date, 
		MAX(visit_date) AS last_visit
	FROM active_cust ac
	JOIN visit vi ON ac.subscription_id=vi.subscription_id
	WHERE end_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '14 days'
	GROUP BY customer_id, ac.vehicle_id, ac.subscription_id, end_date
	HAVING MAX(visit_date) < CURRENT_DATE - INTERVAL '60 days'
)

SELECT * FROM churn_risk
ORDER BY last_visit;

/*===========================================================================================================================================================*/

--Query 6: Customer Engagement Score

--Purpose: Calculate an engagement score to evaluate how actively each customer uses their subscription. Then, display the top 3 most engaged customers per city.
--Formula: (total visits / max visits per month) x recent activity score
	--total visits = number of visits under the customer's most recent active subscription
	--max visits per month = based on plan; normalized to 30 for Diamond Plan (plan_id = 4).
	--recent activity score =
		--10.0 -> if last visit <= 7 days ago
		--7.5 -> if last visit > 7 days ago and <= 15 days
		--5.0 -> if last visit > 15 days ago

--Notes:
	--Replace DATE '2025-06-11' with CURRENT_DATE in real-time usage.
	--This query supports targeted loyalty programs or usage-based reward campaigns.

--SQL features: Common Table Expression (CTE), CASE WHEN, COUNT(), INTERVAL, ROUND(), CONCAT(), and ROW_NUMBER().

WITH normalized_plan AS(
	SELECT
		plan_id,
		CASE WHEN plan_id=4 THEN 30 ELSE max_visit_per_month END AS max_visit --Normalize max_visit_per_month to 30 for plan_id 4 (Diamond Plan).
	FROM plan
),
calculation_input AS(
	SELECT
		customer_id,
		s.vehicle_id AS vehicle_id,
		COUNT(visit_id)::FLOAT AS total_visit, --Count the total visits per vehicle, cast as a float.
		max_visit,
		CASE
			WHEN MAX(visit_date) >= DATE '2025-06-11' - INTERVAL '7 days' THEN 10.0 --Replace with CURRENT_DATE for dynamic filtering
			WHEN MAX(visit_date) >= DATE '2025-06-11' - INTERVAL '15 days' THEN 7.5 --Replace with CURRENT_DATE for dynamic filtering
			ELSE 5.0
		END AS activity_score
	FROM subscription s
	JOIN normalized_plan np ON np.plan_id=s.plan_id
	LEFT JOIN visit v ON s.subscription_id=v.subscription_id
	WHERE is_active=1
	GROUP BY customer_id, s.vehicle_id, max_visit
),
engagement_score AS(
	SELECT
		c.customer_id,
		city_id,
		ROUND(SUM((total_visit/max_visit) * activity_score)::NUMERIC/COUNT(vehicle_id),2) AS engagement_score --Calculate each customer's average engagement score.
	FROM calculation_input ci
	JOIN customer c ON c.customer_id = ci.customer_id
	GROUP BY c.customer_id
),
top_customer AS(
	SELECT
		city_name,
		CONCAT(first_name, ' ', last_name) AS customer_name,
		email AS customer_email,
		phone_number AS customer_phone,
		engagement_score,
		--Rank customers based on their engagement score per city. If multiple customers have equal scores, they will be ranked by their created_date.
		ROW_NUMBER() OVER(PARTITION BY es.city_id ORDER BY engagement_score DESC, created_date ASC) AS engagement_rank
	FROM engagement_score es
	JOIN city ci ON es.city_id=ci.city_id
	JOIN customer c ON es.customer_id=c.customer_id
)

SELECT * FROM top_customer
WHERE engagement_rank BETWEEN 1 AND 3; --Only show the top 3 customers per city.