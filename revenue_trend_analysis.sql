--Query 1: Total Revenue per Month.

--Purpose: Calculate total revenue per month for the past 6 months.
--Notes: This calculation can be adjusted to other time frames by modifying the WHERE clause.

--SQL features: Common Table Expression (CTE), DATE_TRUNC(), TO_CHAR(), SUM(), INTERVAL, GROUP BY, and ORDER BY (ASC)

WITH revenue_per_month AS(
	SELECT
		DATE_TRUNC('MONTH', payment_date) AS month, --Extract month from the payment_date.
		'Rp ' || TO_CHAR(SUM(amount), 'FM9G999G999G999.00') AS total_revenue --Format total_revenue as Indonesian Rupiah with thousand separators and 2 decimal places.
	FROM payment
	WHERE payment_date >= DATE_TRUNC('MONTH', CURRENT_DATE) - INTERVAL '5 Months' --Adjust the time frame here.
	GROUP BY month
)

SELECT
	TO_CHAR(month, 'FMMonth yyyy') AS month_year, --Format month to 'Month yyyy' (e.g. 'June 2025')
	total_revenue
FROM revenue_per_month
ORDER BY month ASC

/*==========================================================================================================================================================*/

--Query 2: Top 5 Cities by Total Revenue.

--Purpose: Identify the top 5 cities by total revenue this year.

--SQL features: Common Table Expression (CTE), SUM(), INNER JOIN, DATE_TRUNC(), GROUP BY, CONCAT(), and ORDER BY (DESC, LIMIT).

WITH revenue_per_city AS(
	SELECT
		city_name,
		SUM(amount) AS total_revenue
	FROM customer c
	JOIN payment p ON c.customer_id=p.customer_id
	JOIN city ci ON c.city_id=ci.city_id
	WHERE payment_date >= DATE_TRUNC('YEAR', CURRENT_DATE) --Include only payments made within the current calendar year.
	GROUP BY c.city_id, city_name --Group revenue by city to calculate total per city.
)

SELECT
	city_name,
	'Rp ' || TO_CHAR(total_revenue, 'FM9G999G999G999.00') AS total_revenue_this_year --Format total_revenue as Indonesian Rupiah with thousand separators and 2 decimal places.
FROM revenue_per_city
ORDER BY total_revenue DESC LIMIT 5 --Only show top 5 cities.

/*==========================================================================================================================================================*/

--Query 3: Month-over-Month Revenue Growth.

--Purpose: Compare month-over-month (MoM) revenue growth rate.
--Formula: (next month revenue - current month revenue) / current month revenue * 100%

--SQL features: Common Table Expression (CTE), DATE_TRUNC(), INTERVAL, SUM(), TO_CHAR(), MAX(), COUNT(), and ROUND().

WITH revenue_per_month AS(
	SELECT
		DATE_TRUNC('MONTH', payment_date) AS month,
		SUM(amount) AS total_revenue
	FROM payment
	WHERE payment_date >= DATE_TRUNC('YEAR', CURRENT_DATE) --Include only payments made from January of the current year.
	GROUP BY month
),
mom_input AS(
	SELECT
		month AS month_year,
		TO_CHAR(month, 'FMMonth') || ' vs ' || TO_CHAR(month + INTERVAL '1 months', 'FMMonth yyyy') AS month_of_month, --Format month_of_month to 'Current Month vs Next Month yyyy' style (e.g. 'March vs April 2025').
		total_revenue,
		LEAD(total_revenue) OVER(ORDER BY month) AS next_month_revenue --Show the next month's revenue from the current row, based on chronological order.
	FROM revenue_per_month
),
mom_calculation AS(
	SELECT
		*,
		TO_CHAR(ROUND(((next_month_revenue-total_revenue)::FLOAT/total_revenue)::NUMERIC,2)*100, 'FM9G999.00') ||'%' AS mom_rate --Calculate and format MoM growth rate as percentage (e.g. '100.00%')
	FROM mom_input
)

SELECT
	month_of_month,
	mom_rate
FROM mom_calculation
WHERE next_month_revenue IS NOT NULL --Only show rows where the calculation is possible.
ORDER BY month_year ASC

/*==========================================================================================================================================================*/

--Query 4: Forecasting using Moving Average.

--Forecast next month's revenue using a simple moving average of the past 3 months. Shorter moving average = more responsive; longer = smoother but less reactive.
--Notes: The length of moving average can be adjusted by modifying the WHERE clause.
--Formula: average revenue over the past 3 months = total revenue / number of months

--SQL features: Common Table Expression (CTE), DATE_TRUNC(), INTERVAL, SUM(), TO_CHAR(), MAX(), COUNT(), and ROUND().

WITH revenue_per_month AS(
	SELECT
		DATE_TRUNC('MONTH', payment_date) AS month_year,
		SUM(amount) AS total_revenue
	FROM payment
	WHERE payment_date >= DATE_TRUNC('MONTH', CURRENT_DATE) - INTERVAL '3 Months' --Filter only total revenue for the past 3 months.
	GROUP BY month_year
)

SELECT
	TO_CHAR(MAX(month_year) + INTERVAL '1 Months', 'FMMonth yyyy') AS next_month, --Forecasted month (the month following the most recent one in the dataset).
	'Rp ' || TO_CHAR(ROUND(SUM(total_revenue)::NUMERIC/COUNT(month_year),2), 'FM9G999G999G999.00') AS price_prediction --Format price_prediction to 'Rp #,###,###.##' style.
FROM revenue_per_month

/*==========================================================================================================================================================*/

--Query 5: Average Revenue per Customer.

--Purpose: Track average revenue per customer per month to observe spending trends.
--Notes: Useful for revenue trend analysis to see if customer value is growing or declining.
--Formula: total monthly revenue divided by number of unique paying customers that month

--SQL features: Common Table Expression (CTE), DATE_TRUNC(), COUNT(DISTINCT), SUM(), TO_CHAR(), and ROUND().

WITH avg_customer_revenue AS(
	SELECT
		DATE_TRUNC('MONTH', payment_date) AS month,
		COUNT(DISTINCT customer_id) AS customer_count,
		SUM(amount)::FLOAT AS total_revenue
	FROM payment
	WHERE payment_date >= DATE_TRUNC('YEAR', CURRENT_DATE) --Filter only total revenue this year.
	GROUP BY month
)

SELECT
	TO_CHAR(month, 'FMMonth yyyy') AS month_year,
	'Rp ' || TO_CHAR(ROUND((total_revenue/NULLIF (customer_count,0))::NUMERIC,2), 'FM9G999G999G999.00') AS average_revenue_per_customer
FROM avg_customer_revenue