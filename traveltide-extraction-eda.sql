-- TravelTide - segment customer data according to business needs and deliver data-driven recommendations

-- postgres://Test:bQNxVzJL4g6u@ep-noisy-flower-846766.us-east-2.aws.neon.tech/TravelTide


-- exploring database

-- What columns are in your database?
SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema = 'public';

--------

-- A VIEW of all your columns
-- 1) Create a new view called table_columns
CREATE VIEW table_columns AS
SELECT table_name,
	   STRING_AGG(column_name, ', ') AS columns
FROM information_schema.columns
WHERE table_schema = 'public'
GROUP BY table_name;
-- 2) Query the newly created view table_columns
SELECT *
FROM table_columns;


-----------------------------------------------------------------------------
-----------------------------------------------------------------------------

-- all data for cohort
WITH cohort AS
    -- cohort definition
    (SELECT DISTINCT user_id
    FROM sessions
    WHERE session_start >= DATE '2023-01-04'
    GROUP BY sessions.user_id
    HAVING COUNT(*) > 7)

SELECT *
FROM sessions
LEFT JOIN users
ON sessions.user_id = users.user_id
LEFT JOIN flights
ON sessions.trip_id = flights.trip_id
LEFT JOIN hotels
ON sessions.trip_id = hotels.trip_id
WHERE sessions.user_id IN (SELECT user_id FROM cohort)
	AND session_start >= DATE '2023-01-04'
ORDER BY sessions.user_id;

-----------------------------------------------------------------------------
-----------------------------------------------------------------------------
/*
Segments:
1) Free hotel meal  - If the average hotel discount amount is 0 for a user, they will be categorized into the "Free hotel meal" segment.
2) Free checked bag - If the average number of checked bags is 0 for a user's flights, they will be categorized into the "Free checked bag" segment.
3) no cancellation fees - "No cancellation fees" segment: Users with a total sum of cancellations (sessions.cancellation::int) is greater than 0.
4) exclusive discounts - when bargain_hunter_index > 0.0001. (bargain_hunter_index = ASD_per_km*discount_flight_proportion*average_flight_discount)
5) 1 night free hotel with flight - Users who have booked at least one flight (sessions.flight_booked) and have not booked hotels (sessions.hotel_booked)
*/

-- All aggregates + segments

WITH cohort AS
    -- cohort definition
    (SELECT DISTINCT user_id
    FROM sessions
    WHERE session_start >= DATE '2023-01-04'
    GROUP BY sessions.user_id
    HAVING COUNT(*) > 7)

SELECT
    sessions.user_id,

    -- base aggregates:sessions
    SUM(sessions.flight_discount::int) AS num_flight_discount,
    SUM(sessions.hotel_discount::int) AS num_hotel_discount,
	AVG(sessions.flight_discount_amount) AS avg_flight_discount_amount,
	AVG(sessions.hotel_discount_amount) AS avg_hotel_discount_amount,
    SUM(sessions.flight_booked::int) AS num_flight_booked,
    SUM(sessions.hotel_booked::int) AS num_hotel_booked,
    AVG(sessions.page_clicks) AS avg_page_clicks,
    MIN(sessions.page_clicks) AS min_page_clicks,
    MAX(sessions.page_clicks) AS max_page_clicks,
    STDDEV(sessions.page_clicks) AS std_page_clicks,
    SUM(sessions.cancellation::int) AS num_cancellation,

    -- base aggregates:flights
    SUM(flights.seats) AS total_seats,
    AVG(flights.seats) AS avg_seats,
    MIN(flights.seats) AS min_seats,
    MAX(flights.seats) AS max_seats,
    SUM(flights.return_flight_booked::int) AS num_return_flight_booked,
    SUM(flights.checked_bags) AS total_checked_bags,
    AVG(flights.checked_bags) AS avg_checked_bags,
    MIN(flights.checked_bags) AS min_checked_bags,
    MAX(flights.checked_bags) AS max_checked_bags,
    SUM(flights.base_fare_usd) AS total_base_fare_usd,
    AVG(flights.base_fare_usd) AS avg_base_fare_usd,
    MIN(flights.base_fare_usd) AS min_base_fare_usd,
    MAX(flights.base_fare_usd) AS max_base_fare_usd,
    STDDEV(flights.base_fare_usd) AS std_base_fare_usd,

    -- base aggregates:hotels
    SUM(hotels.rooms) AS total_rooms,
    AVG(hotels.rooms) AS avg_rooms,
    MIN(hotels.rooms) AS min_rooms,
    MAX(hotels.rooms) AS max_rooms,
    SUM(hotels.hotel_per_room_usd) AS total_hotel_per_room_usd,
    AVG(hotels.hotel_per_room_usd) AS avg_hotel_per_room_usd,
    MIN(hotels.hotel_per_room_usd) AS min_hotel_per_room_usd,
    MAX(hotels.hotel_per_room_usd) AS max_hotel_per_room_usd,
    STDDEV(hotels.hotel_per_room_usd) AS std_hotel_per_room_usd,

    -- base aggregates:users
    users.birthdate,
    DATE_PART('year', AGE(CURRENT_DATE, users.birthdate)) AS age,
    users.gender,
    users.married::int,
    users.has_children::int,
    users.home_country,
    users.home_city,
    users.home_airport,
    users.home_airport_lat,
    users.home_airport_lon,
    users.sign_up_date,
		((12 * (DATE_PART('year', AGE(CURRENT_DATE, users.sign_up_date)))) + DATE_PART('month', AGE(CURRENT_DATE, users.sign_up_date))) AS sign_up_since_months,

    -----------------------------

    -- percentage of flight purchases made with a discount
    SUM(CASE WHEN flight_discount THEN 1 ELSE 0 END)::FLOAT / COUNT(*) AS discount_flight_proportion,
    -- average discount size on flight purchases
    AVG(flight_discount_amount) AS average_flight_discount,
    -- dollars saved
    AVG(flight_discount_amount * base_fare_usd) AS ADS,
    -- dollars saved per kilometer
    SUM(flight_discount_amount * base_fare_usd) / SUM(haversine_distance(users.home_airport_lat, users.home_airport_lon, flights.destination_airport_lat, flights.destination_airport_lon)) AS ADS_per_km,

    -- -- percentage of hotel purchases made with a discount
    SUM(CASE WHEN hotel_discount THEN 1 ELSE 0 END)::FLOAT / COUNT(*) AS discount_hotel_proportion,
    -- average discount size on hotel purchases
    AVG(hotel_discount_amount) AS average_hotel_discount,
    -- dollars saved
    AVG(hotel_discount_amount * hotel_per_room_usd) AS ADS_hotel,

    -- mean session time in seconds
    AVG(EXTRACT(EPOCH FROM (session_end - session_start))) AS mean_session_time_sec,

    -- Calculate the bargain_hunter_index
    (SUM(flight_discount_amount * base_fare_usd) / SUM(haversine_distance(users.home_airport_lat, users.home_airport_lon, flights.destination_airport_lat, flights.destination_airport_lon))) * (SUM(CASE WHEN flight_discount THEN 1 ELSE 0 END)::FLOAT / COUNT(*)) * AVG(flight_discount_amount) AS bargain_hunter_index,

    -----------------------------

    -- Segment: Free hotel meal
    CASE WHEN AVG(COALESCE(hotel_discount_amount, 0)) = 0 OR AVG(hotel_discount_amount) IS NULL THEN 1 ELSE 0 END AS free_hotel_meal_segment,

    -- Segment: Free checked bag
	CASE WHEN AVG(COALESCE(flights.checked_bags, 0)) = 0 OR AVG(flights.checked_bags) IS NULL THEN 1 ELSE 0 END AS free_checked_bag_segment,

    -- Segment: No cancellation fees
    CASE WHEN SUM(sessions.cancellation::int) > 0 THEN 1 ELSE 0 END AS no_cancellation_fees_segment,

    -- Segment: Exclusive discounts
    CASE WHEN (SUM(flight_discount_amount * base_fare_usd) / SUM(haversine_distance(users.home_airport_lat, users.home_airport_lon, flights.destination_airport_lat, flights.destination_airport_lon))) * (SUM(CASE WHEN flight_discount THEN 1 ELSE 0 END)::FLOAT / COUNT(*)) * AVG(flight_discount_amount) > 0.0001 THEN 1 ELSE 0 END AS exclusive_discounts_segment, -- Adjust the threshold as needed

    -- Segment: 1 night free hotel with flight
	CASE WHEN
    SUM(CASE WHEN sessions.flight_booked::int > 0 THEN 1 ELSE 0 END) > 0  -- Check if there are booked flights
    AND
    SUM(CASE WHEN sessions.hotel_booked::int > 0 THEN 1 ELSE 0 END) = 0  -- Check if there are no booked hotels
	THEN 1 ELSE 0 END AS one_night_hotel_free_with_flight_segment

FROM sessions
LEFT JOIN users
ON sessions.user_id = users.user_id
LEFT JOIN flights
ON sessions.trip_id = flights.trip_id
LEFT JOIN hotels
ON sessions.trip_id = hotels.trip_id
WHERE sessions.user_id IN (SELECT user_id FROM cohort)
	AND session_start >= DATE '2023-01-04'
GROUP BY
    sessions.user_id,
    users.birthdate,
    users.gender,
    users.married,
    users.has_children,
    users.home_country,
    users.home_city,
    users.home_airport,
    users.home_airport_lat,
    users.home_airport_lon,
    users.sign_up_date
ORDER BY sessions.user_id;


-----------------------------------------------------------------------------
-----------------------------------------------------------------------------

-- segments only
/*
Segments:
1) Free hotel meal  - If the average hotel discount amount is 0 for a user, they will be categorized into the "Free hotel meal" segment.
2) Free checked bag - If the average number of checked bags is 0 for a user's flights, they will be categorized into the "Free checked bag" segment.
3) no cancellation fees - "No cancellation fees" segment: Users with a total sum of cancellations (sessions.cancellation::int) is greater than 0.
4) exclusive discounts - when bargain_hunter_index > 0.0001. (bargain_hunter_index = ASD_per_km*discount_flight_proportion*average_flight_discount)
5) 1 night free hotel with flight - Users who have booked at least one flight (sessions.flight_booked) and have not booked hotels (sessions.hotel_booked)
*/
WITH cohort AS
    -- cohort definition
    (SELECT DISTINCT user_id
    FROM sessions
    WHERE session_start >= DATE '2023-01-04'
    GROUP BY sessions.user_id
    HAVING COUNT(*) > 7)

SELECT
    sessions.user_id,

    -- Segment: Free hotel meal
    CASE WHEN AVG(COALESCE(hotel_discount_amount, 0)) = 0 OR AVG(hotel_discount_amount) IS NULL THEN 1 ELSE 0 END AS free_hotel_meal_segment,

    -- Segment: Free checked bag
	CASE WHEN AVG(COALESCE(flights.checked_bags, 0)) = 0 OR AVG(flights.checked_bags) IS NULL THEN 1 ELSE 0 END AS free_checked_bag_segment,

    -- Segment: No cancellation fees
    CASE WHEN SUM(sessions.cancellation::int) > 0 THEN 1 ELSE 0 END AS no_cancellation_fees_segment,

    -- Segment: Exclusive discounts
    CASE WHEN (SUM(flight_discount_amount * base_fare_usd) / SUM(haversine_distance(users.home_airport_lat, users.home_airport_lon, flights.destination_airport_lat, flights.destination_airport_lon))) * (SUM(CASE WHEN flight_discount THEN 1 ELSE 0 END)::FLOAT / COUNT(*)) * AVG(flight_discount_amount) > 0.0001 THEN 1 ELSE 0 END AS exclusive_discounts_segment, -- Adjust the threshold as needed

    -- Segment: 1 night free hotel with flight
	CASE WHEN
    SUM(CASE WHEN sessions.flight_booked::int > 0 THEN 1 ELSE 0 END) > 0  -- Check if there are booked flights
    AND
    SUM(CASE WHEN sessions.hotel_booked::int > 0 THEN 1 ELSE 0 END) = 0  -- Check if there are no booked hotels
	THEN 1 ELSE 0 END AS one_night_hotel_free_with_flight_segment

FROM sessions
LEFT JOIN users
ON sessions.user_id = users.user_id
LEFT JOIN flights
ON sessions.trip_id = flights.trip_id
LEFT JOIN hotels
ON sessions.trip_id = hotels.trip_id
WHERE sessions.user_id IN (SELECT user_id FROM cohort)
	AND session_start >= DATE '2023-01-04'
GROUP BY sessions.user_id
ORDER BY sessions.user_id;

-----------------------------------------------------------------------------
-----------------------------------------------------------------------------

-- count_per_segments only
/*
Segments:
1) Free hotel meal  - If the average hotel discount amount is 0 for a user, they will be categorized into the "Free hotel meal" segment.
2) Free checked bag - If the average number of checked bags is 0 for a user's flights, they will be categorized into the "Free checked bag" segment.
3) no cancellation fees - "No cancellation fees" segment: Users with a total sum of cancellations (sessions.cancellation::int) is greater than 0.
4) exclusive discounts - when bargain_hunter_index > 0.0001. (bargain_hunter_index = ASD_per_km*discount_flight_proportion*average_flight_discount)
5) 1 night free hotel with flight - Users who have booked at least one flight (sessions.flight_booked) and have not booked hotels (sessions.hotel_booked)
*/
WITH cohort AS
    -- cohort definition
    (SELECT DISTINCT user_id
    FROM sessions
    WHERE session_start >= DATE '2023-01-04'
    GROUP BY sessions.user_id
    HAVING COUNT(*) > 7),

segmented_users AS
    (SELECT
    sessions.user_id,

    -- Segment: Free hotel meal
    CASE WHEN AVG(COALESCE(hotel_discount_amount, 0)) = 0 OR AVG(hotel_discount_amount) IS NULL THEN 1 ELSE 0 END AS free_hotel_meal_segment,

    -- Segment: Free checked bag
	CASE WHEN AVG(COALESCE(flights.checked_bags, 0)) = 0 OR AVG(flights.checked_bags) IS NULL THEN 1 ELSE 0 END AS free_checked_bag_segment,

    -- Segment: No cancellation fees
    CASE WHEN SUM(sessions.cancellation::int) > 0 THEN 1 ELSE 0 END AS no_cancellation_fees_segment,

    -- Segment: Exclusive discounts
    CASE WHEN (SUM(flight_discount_amount * base_fare_usd) / SUM(haversine_distance(users.home_airport_lat, users.home_airport_lon, flights.destination_airport_lat, flights.destination_airport_lon))) * (SUM(CASE WHEN flight_discount THEN 1 ELSE 0 END)::FLOAT / COUNT(*)) * AVG(flight_discount_amount) > 0.0001 THEN 1 ELSE 0 END AS exclusive_discounts_segment, -- Adjust the threshold as needed

    -- Segment: 1 night free hotel with flight
	CASE WHEN
    SUM(CASE WHEN sessions.flight_booked::int > 0 THEN 1 ELSE 0 END) > 0  -- Check if there are booked flights
    AND
    SUM(CASE WHEN sessions.hotel_booked::int > 0 THEN 1 ELSE 0 END) = 0  -- Check if there are no booked hotels
	THEN 1 ELSE 0 END AS one_night_hotel_free_with_flight_segment

    FROM sessions
    LEFT JOIN users
    ON sessions.user_id = users.user_id
    LEFT JOIN flights
    ON sessions.trip_id = flights.trip_id
    LEFT JOIN hotels
    ON sessions.trip_id = hotels.trip_id
    WHERE sessions.user_id IN (SELECT user_id FROM cohort)
	    AND session_start >= DATE '2023-01-04'
    GROUP BY sessions.user_id
    ORDER BY sessions.user_id)

SELECT
    SUM(free_checked_bag_segment) AS total_free_checked_bag_segment,
    SUM(free_hotel_meal_segment) AS total_free_hotel_meal_segment,
    SUM(no_cancellation_fees_segment) AS total_no_cancellation_fees_segment,
    SUM(exclusive_discounts_segment) AS total_exclusive_discounts_segment,
    SUM(one_night_hotel_free_with_flight_segment) AS total_one_night_hotel_free_with_flight_segment,
    COUNT(user_id) AS total_users
FROM segmented_users;

/*
| total_free_checked_bag_segment | total_free_hotel_meal_segment | total_no_cancellation_fees_segment | total_exclusive_discounts_segment | total_one_night_hotel_free_with_flight_segment | total_users |
| ------------------------------ | ----------------------------- | ---------------------------------- | --------------------------------- | ---------------------------------------------- | ----------- |
| 1903                           | 1989                          | 595                                | 1272                              | 89                                             | 5998        |
*/
-----------------------------------------------------------------------------
-----------------------------------------------------------------------------

/*
Note: This basic customer segmentation is a good starting point for further analysis and updated later
 using Fuzzy segmentation and Clustering in python jupyter notebooks.
*/