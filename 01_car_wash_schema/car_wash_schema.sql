/*
I use PostgreSQL and created a database first. The database is called "car_wash", but feel free to rename it if you'd like.
car_wash records data from subscription-based car wash businesses, including customer demographic information and subscription behavior.
This script is designed to create tables, their relationships, and indexes.
*/

--Query to create province table
CREATE TABLE province(
	province_id SERIAL PRIMARY KEY,
	province_name VARCHAR(50) NOT NULL
);

--Query to create city table
CREATE TABLE city(
	city_id SERIAL PRIMARY KEY,
	province_id INT REFERENCES province(province_id) ON UPDATE CASCADE ON DELETE CASCADE,
	city_name VARCHAR(50) NOT NULL
);

--Query to create customer table
CREATE TABLE customer(
	customer_id SERIAL PRIMARY KEY,
	first_name VARCHAR(50),
	last_name VARCHAR(50),
	city_id INT REFERENCES city(city_id) ON UPDATE CASCADE ON DELETE CASCADE,
	address VARCHAR(255) NOT NULL,
	gender CHAR(1) CHECK(gender IN('M','F')) NOT NULL,
	date_of_birth DATE CHECK(date_of_birth <= CURRENT_DATE - INTERVAL '18 years') NOT NULL,
	phone_number VARCHAR(20) NOT NULL,
	email VARCHAR(50) NOT NULL,
	password VARCHAR(50) NOT NULL,
	picture_url VARCHAR(100) NOT NULL,
	created_date TIMESTAMP NOT NULL,
	last_update TIMESTAMP
);

--Query to create (vehicle) brand table
CREATE TABLE brand(
	vehicle_brand_id SERIAL PRIMARY KEY,
	vehicle_brand_name VARCHAR(50) NOT NULL
);

--Query to create (vehicle) type table
CREATE TABLE type(
	vehicle_type_id SERIAL PRIMARY KEY,
	vehicle_brand_id INT REFERENCES brand(vehicle_brand_id) ON UPDATE CASCADE ON DELETE CASCADE,
	vehicle_type VARCHAR(50)
);

--Query to create vehicle table.
CREATE TABLE vehicle(
	vehicle_id SERIAL PRIMARY KEY,
	customer_id INT REFERENCES customer(customer_id) ON UPDATE CASCADE ON DELETE CASCADE,
	vehicle_type_id INT REFERENCES type(vehicle_type_id) ON UPDATE CASCADE ON DELETE CASCADE,
	license_plate VARCHAR(10) NOT NULL,
	color VARCHAR(20) NOT NULL
);

--Query to create customer_id index in vehicle table.
CREATE INDEX idx_vehicle_customer ON vehicle(customer_id);

--Query to create store table.
CREATE TABLE store(
	store_id SERIAL PRIMARY KEY,
	city_id INT REFERENCES city(city_id) ON UPDATE CASCADE ON DELETE CASCADE,
	address VARCHAR(255) NOT NULL
);

--Query to create (subscription) plan table.
CREATE TABLE plan(
	plan_id SERIAL PRIMARY KEY,
	plan_name VARCHAR(50),
	price NUMERIC(19,0),
	max_visit_per_month INT CHECK (max_visit_per_month IN (4, 8, 12, 100)) NOT NULL,
	description VARCHAR(255) NOT NULL
);

--Query to create (payment) method table.
CREATE TABLE method(
	payment_method_id SERIAL PRIMARY KEY,
	payment_method VARCHAR(50) NOT NULL
);

--Query to create payment (history) table.
CREATE TABLE payment(
	payment_id SERIAL PRIMARY KEY,
	customer_id INT REFERENCES customer(customer_id) ON UPDATE CASCADE ON DELETE CASCADE,
	payment_method_id INT REFERENCES method(payment_method_id) ON UPDATE CASCADE ON DELETE CASCADE,
	amount NUMERIC(19,0),
	payment_date TIMESTAMP
);

--Query to create customer_id, payment_date index in payment table (composite index).
CREATE INDEX idx_payment_customer_date ON payment(customer_id, payment_date);

--Query to create payment_date index in payment table.
CREATE INDEX idx_payment_date ON payment(payment_date);

--Query to create subscription table.
CREATE TABLE subscription(
	subscription_id SERIAL PRIMARY KEY,
	customer_id INT REFERENCES customer(customer_id) ON UPDATE CASCADE ON DELETE CASCADE,
	vehicle_id INT REFERENCES vehicle(vehicle_id) ON UPDATE CASCADE ON DELETE CASCADE,
	plan_id INT REFERENCES plan(plan_id) ON UPDATE CASCADE ON DELETE CASCADE,
	payment_id INT REFERENCES payment(payment_id) ON UPDATE CASCADE ON DELETE CASCADE,
	store_id INT REFERENCES store(store_id) ON UPDATE CASCADE ON DELETE CASCADE,
	start_date DATE NOT NULL,
	end_date DATE NOT NULL,
	is_active SMALLINT CHECK (is_active BETWEEN 0 AND 1) NOT NULL
);

--Query to create customer_id, vehicle_id index in subscription table (composite index).
CREATE INDEX idx_subscription_customer_vehicle ON subscription(customer_id, vehicle_id);

--Query to create date range index in subscription table (composite index).
CREATE INDEX idx_subscription_dates ON subscription(start_date, end_date);

--Query to create payment_id index in subscription table.
CREATE INDEX idx_subscription_payment ON subscription(payment_id);

--Query to create store_id index in subscription table.
CREATE INDEX idx_subscription_store ON subscription(store_id);

--Query to create visit table.
CREATE TABLE visit(
	visit_id SERIAL PRIMARY KEY,
	subscription_id INT REFERENCES subscription(subscription_id) ON UPDATE CASCADE ON DELETE CASCADE,
	vehicle_id INT REFERENCES vehicle(vehicle_id) ON UPDATE CASCADE ON DELETE CASCADE,
	store_id INT REFERENCES store(store_id) ON UPDATE CASCADE ON DELETE CASCADE,
	visit_date TIMESTAMP NOT NULL,
	notes VARCHAR(255),
	rating INT CHECK (rating BETWEEN 1 AND 5) NOT NULL,
	feedback VARCHAR (255) NOT NULL
);

--Query to create subscription_id index in visit table.
CREATE INDEX idx_visit_subscription ON visit(subscription_id);

--Query to create vehicle_id index in visit table.
CREATE INDEX idx_visit_vehicle ON visit(vehicle_id);

--Query to create store_id, visit_date index in visit table (composite index).
CREATE INDEX idx_visit_store_date ON visit(store_id, visit_date);

--Query to create visit_date index in visit table.
CREATE INDEX idx_visit_date ON visit(visit_date);